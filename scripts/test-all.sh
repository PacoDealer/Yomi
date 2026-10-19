#!/bin/bash
# Runs every macOS-compiled test suite in scripts/*-tests + check-bundle-docs.py (S184). Yomi has no unit-test target: each suite compiles the
# pure-Foundation file(s) it tests with swiftc and runs them. UI tests (YomiUITests) are separate — see CLAUDE.md.
# Usage: scripts/test-all.sh            exit code = number of failed suites
cd "$(dirname "$0")"
failed=()
for run in */run.sh; do
  suite="${run%/run.sh}"
  # rar-extract-tests needs .cbr files passed as arguments, so it isn't part of the automatic run.
  [[ "$suite" == "rar-extract-tests" ]] && continue
  if out=$(bash "$run" 2>&1); then
    printf "PASS  %-28s %s\n" "$suite" "$(echo "$out" | tail -1)"
  else
    printf "FAIL  %-28s\n" "$suite"
    echo "$out" | tail -20 | sed 's/^/      /'
    failed+=("$suite")
  fi
done
if out=$(python3 check-bundle-docs.py 2>&1); then
  printf "PASS  %-28s %s\n" "check-bundle-docs" "$out"
else
  printf "FAIL  %-28s\n" "check-bundle-docs"; echo "$out" | sed 's/^/      /'; failed+=("check-bundle-docs")
fi
echo
if (( ${#failed[@]} )); then echo "${#failed[@]} suite(s) failed: ${failed[*]}"; else echo "All suites passed."; fi
exit ${#failed[@]}
