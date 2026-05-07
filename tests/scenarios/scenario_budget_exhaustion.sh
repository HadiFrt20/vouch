#!/usr/bin/env bash
# Scenario 2 — budget exhaustion mid-run.
#
# 3 stages with cost 2 each; wallet has 5. Stage 3 is debited but should
# fail (insufficient → exit 2). Run must end as `failed` with stage 3
# marked `skipped` and reason "budget exhausted".

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"

PROJECT=$(mktemp -d -t vouch-budget-XXXXXX)
trap "rm -rf $PROJECT" EXIT
RUN_DIR="$PROJECT/.vouch/runs/r1"
WALLET="$PROJECT/.vouch/budget.json"

python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" \
    --phase a:33 --phase b:33 --phase c:34 --id r1 >/dev/null
python3 "$HELPERS/vouch_budget.py" init "$WALLET" --balance 5 \
    --cost-per-stage '{"a":2,"b":2,"c":2}' >/dev/null

run_stage() {
    local s=$1
    if python3 "$HELPERS/vouch_budget.py" debit "$WALLET" --stage "$s" >/dev/null 2>&1; then
        python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase "$s" --status running >/dev/null
        echo '{"ok":true}' > "$RUN_DIR/$s.result.json"
        python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase "$s" --status completed \
            --result-file "$RUN_DIR/$s.result.json" >/dev/null
        return 0
    else
        # Insufficient — mirror what /vouch-run does
        python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase "$s" --status skipped \
            --error "budget exhausted" >/dev/null
        python3 "$HELPERS/vouch_state.py" finish "$RUN_DIR" --status failed \
            --error "budget exhausted at $s" >/dev/null
        return 1
    fi
}

run_stage a
run_stage b
if run_stage c; then
    echo "FAIL: stage c should have been blocked by budget" >&2
    exit 1
fi

# Verify
RESULT=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR")
status=$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
c_status=$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["phases"]["c"]["status"])')
c_error=$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["phases"]["c"]["error"])')
balance=$(python3 "$HELPERS/vouch_budget.py" show "$WALLET" | python3 -c 'import sys,json; print(json.load(sys.stdin)["balance"])')

if [[ "$status" != "failed" ]]; then echo "FAIL: status=$status" >&2; exit 1; fi
if [[ "$c_status" != "skipped" ]]; then echo "FAIL: c.status=$c_status" >&2; exit 1; fi
if [[ "$c_error" != "budget exhausted" ]]; then echo "FAIL: c.error=$c_error" >&2; exit 1; fi
if [[ "$balance" != "1" ]]; then echo "FAIL: balance=$balance (expected 1: 5 - 2 - 2)" >&2; exit 1; fi

echo "OK: scenario_budget_exhaustion — c.status=skipped balance=$balance run=$status"
