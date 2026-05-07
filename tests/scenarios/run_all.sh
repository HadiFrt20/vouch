#!/usr/bin/env bash
# Run every scenario in this directory; print a summary; exit non-zero on any failure.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

shopt -s nullglob
scenarios=( "$HERE"/scenario_*.sh )
if [[ ${#scenarios[@]} -eq 0 ]]; then
    echo "no scenarios found in $HERE" >&2
    exit 1
fi

passed=0
failed=0
fail_list=()

start=$SECONDS
for s in "${scenarios[@]}"; do
    out=$(bash "$s" 2>&1) && rc=0 || rc=$?
    if [[ $rc -eq 0 ]]; then
        echo "✓ $(basename "$s")"
        passed=$((passed+1))
    else
        echo "✗ $(basename "$s")"
        echo "$out" | sed 's/^/    /'
        failed=$((failed+1))
        fail_list+=("$(basename "$s")")
    fi
done
elapsed=$((SECONDS - start))

echo
echo "─────────────────────────────"
echo "passed: $passed   failed: $failed   elapsed: ${elapsed}s"
if [[ $failed -gt 0 ]]; then
    echo "failures: ${fail_list[*]}"
    exit 1
fi
