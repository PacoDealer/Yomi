#!/bin/bash
# Records a Yomi performance trace on Martin's iPhone 17 (S129 baseline, RESEARCH §23.2):
# Time Profiler + Points of Interest (Perf.swift signposts) + Hitches. Attaches to the running app (phone
# unlocked, Yomi open). Install a Release build first: scripts/build-personal.sh --release
# Usage: scripts/perf/record.sh <name> [seconds=45] [--relaunch]   → perf-traces/<name>.trace, then prints the summary.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
DEVICE_UDID=00008150-00187C4A1EF3401C
NAME="$1"; SECS="${2:-45}"
OUT="$ROOT/perf-traces/$NAME.trace"
mkdir -p "$ROOT/perf-traces"; rm -rf "$OUT"
DEVICE_CORE=270B9EDA-7298-5206-9E67-71C0E8F60CF6
# xctrace --launch times out "waiting for device to boot" on this phone, so launch with devicectl and attach by PID
# (misses the first ~second of launch; LoadLibrary re-runs on every Library appear anyway). Attach by NAME: on S134
# xctrace rejected devicectl's pid ("Cannot find process for provided pid") while --attach Yomi worked. xctrace also
# needs a live CoreDevice tunnel (devicectl state "connected", not "available (paired)") or it fails "Timed out
# waiting for device to boot" — keep one open, e.g. `devicectl device notification observe --name x --session-timeout 7200 &` (--timeout alone still exits at 300 s).
# --relaunch as 3rd arg restarts the app first; by default we attach to the Yomi already open on screen (a relaunch
# while the phone is dimmed leaves the app in the background and the trace records nothing — S129 run 2).
[[ "${3:-}" == "--relaunch" ]] && xcrun devicectl device process launch --device "$DEVICE_CORE" --terminate-existing pacodealer.Yomi >/dev/null
PID=$(set +o pipefail; xcrun devicectl device info processes --device "$DEVICE_CORE" 2>/dev/null | awk '/Yomi\.app\/Yomi *$/ {print $1}' | tail -1)
[ -n "$PID" ] || { echo "Yomi isn't running — open it on the phone first"; exit 1; }
# xctrace resolves the target inconsistently: on S134 the same running app was found by pid and not by name, then
# the reverse, minutes apart. Try both, twice.
# S145 (Xcode 27 xctrace): --attach failed by pid AND name every time; --all-processes works (summarize.py filters Yomi).
for target in ALL "$PID" Yomi; do
  rm -rf "$OUT"
  echo "Recording Yomi (attach $target) for ${SECS}s — go"
  LOG=$(xcrun xctrace record --template 'Time Profiler' --instrument 'Points of Interest' --instrument 'Hitches' \
    --device "$DEVICE_UDID" --time-limit "${SECS}s" --output "$OUT" $([ "$target" = ALL ] && echo --all-processes || echo --attach "$target") 2>&1 | grep -v "^$" | tail -2) || true   # a failed attempt must reach the retry, not kill the script
  echo "$LOG"
  [ -d "$OUT" ] && break
done
[ -d "$OUT" ] || exit 1
# An attached-but-idle app (backgrounded, or nobody touching it) records a handful of samples, not thousands.
SAMPLES=$(xcrun xctrace export --input "$OUT" --xpath '/trace-toc/run[@number="1"]/data/table[@schema="time-profile"]' \
  2>/dev/null | grep -c "<row" || true)
echo "time-profile samples: $SAMPLES"
[ "$SAMPLES" -ge 200 ] || echo "WARNING: almost no samples — Yomi was idle or not in the foreground; redo this run"
"$ROOT/scripts/perf/summarize.py" "$OUT"
