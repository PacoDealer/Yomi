#!/bin/bash
# Performance gates (S179, RESEARCH §25.10 #11): runs YomiUITests/PerfUITests, reads the measured averages from the
# result bundle and fails when one is over its limit in scripts/perf-gates.json.
#
#   scripts/perf-gates.sh                 # simulator (iPhone 17 Pro, iOS 26.3) — launch time + long-strip memory
#   scripts/perf-gates.sh --device <id>   # a connected iPhone — adds the hitch-ratio gates (simulator has none)
#   scripts/perf-gates.sh --result <path> # only check an existing .xcresult
#
# Takes ~6 minutes. Run it alone: other simulator or Mac load skews the numbers.
set -euo pipefail
cd "$(dirname "$0")/.."

DEST="platform=iOS Simulator,id=F31CC190-186D-4598-9ED8-225821907550"
ON_DEVICE=0
RESULT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --device) DEST="platform=iOS,id=$2"; ON_DEVICE=1; shift 2 ;;
    --result) RESULT="$2"; shift 2 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done

if [[ -z "$RESULT" ]]; then
  RESULT="$(mktemp -d)/perf.xcresult"
  echo "Running PerfUITests on $DEST …"
  if ! xcodebuild test -scheme Yomi -destination "$DEST" \
      -derivedDataPath "$HOME/Library/Developer/Xcode/DerivedData/Yomi-perf" \
      -only-testing:YomiUITests/PerfUITests -resultBundlePath "$RESULT" > "${RESULT%.xcresult}.log" 2>&1; then
    echo "PerfUITests failed to run — log: ${RESULT%.xcresult}.log" >&2
    exit 1
  fi
fi

xcrun xcresulttool get test-results metrics --path "$RESULT" --compact > "${RESULT%.xcresult}-metrics.json"
python3 -I - "${RESULT%.xcresult}-metrics.json" scripts/perf-gates.json "$ON_DEVICE" <<'PY'
import json, sys
metrics, gates, on_device = json.load(open(sys.argv[1])), json.load(open(sys.argv[2]))["gates"], sys.argv[3] == "1"
found = {}
for test in metrics:
    name = test["testIdentifier"].split("/")[-1].rstrip("()")
    for run in test.get("testRuns", []):
        for m in run.get("metrics", []):
            values = m.get("measurements") or []
            if values:
                found[(name, m["displayName"])] = sum(values) / len(values)
failed = 0
for g in gates:
    if g.get("deviceOnly") and not on_device:
        print(f"  skip  {g['test']} · {g['metric']} (device only)")
        continue
    hits = [(k[1], v) for k, v in found.items() if k[0] == g["test"] and k[1].startswith(g["metric"])]
    if not hits:
        print(f"  FAIL  {g['test']} · {g['metric']}: not measured")
        failed += 1
        continue
    for display, value in hits:
        ok = value <= g["max"]
        failed += not ok
        print(f"  {'ok  ' if ok else 'FAIL'}  {g['test']} · {display}: {value:.3f} {g['unit']} (limit {g['max']})")
print("Perf gates passed." if not failed else f"{failed} perf gate(s) failed.")
sys.exit(1 if failed else 0)
PY
