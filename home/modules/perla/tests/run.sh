#!/usr/bin/env bash
# Runs every tests/test_*.sh and reports a summary.
#
# Exit 0 only if nothing failed. A test file that SKIPs (e.g. because the
# daemon is not running) does not fail the run — a suite that punishes a
# stopped service just teaches people to ignore it.
#
# Every file gets a PASS:/FAIL: line, and an empty suite prints a loud
# warning. Both exist so a green exit code is never mistaken for coverage
# that did not happen — a runner reached through a symlinked path can find
# zero tests, and "0 passed, 0 failed" alone would read as a pass.
set -uo pipefail

cd "$(dirname "$0")" || exit 1

failed=0
passed=0
skipped=0
found=0

for t in test_*.sh; do
  [ -e "$t" ] || continue
  found=$((found + 1))
  printf '\n=== %s ===\n' "$t"
  out=$(bash "$t" 2>&1); status=$?
  printf '%s\n' "$out"
  skipped=$((skipped + $(printf '%s\n' "$out" | grep -c '^  SKIP  ')))
  if [ "$status" -eq 0 ]; then
    passed=$((passed + 1))
    printf 'PASS: %s\n' "$t"
  else
    failed=$((failed + 1))
    printf 'FAIL: %s\n' "$t"
  fi
done

if [ "$found" -eq 0 ]; then
  printf '\nWARNING: no test files found in %s — nothing was tested.\n' "$(pwd)"
  printf '         This is not a passing run; it is an empty suite.\n'
fi

printf '\n==================================\n'
printf '  %d passed, %d failed, %d skipped\n' "$passed" "$failed" "$skipped"
if [ "$skipped" -gt 0 ]; then
  printf '  %d check(s) did not run — this is NOT a full pass.\n' "$skipped"
fi
[ "$failed" -eq 0 ] || exit 1
