#!/usr/bin/env bash
# Scenario 3 — atomic debit invariant under concurrency.
#
# Spawn N parallel debit processes against a wallet of balance N. Exactly
# N debits should succeed, balance ends at 0. Without the flock, this
# would corrupt and overdraw.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"

PROJECT=$(mktemp -d -t vouch-concurrent-XXXXXX)
trap "rm -rf $PROJECT" EXIT
WALLET="$PROJECT/budget.json"

# Bigger numbers stress the lock harder; 200 is enough to corrupt without flock.
N=200
ATTEMPTS=$((N * 2))   # twice as many attempts as balance — half should fail

python3 "$HELPERS/vouch_budget.py" init "$WALLET" --balance "$N" \
    --cost-per-stage 1 >/dev/null

# Run ATTEMPTS parallel debits, capturing exit codes
SUCC_FILE="$PROJECT/successes"
: > "$SUCC_FILE"

for i in $(seq 1 "$ATTEMPTS"); do
    (
        if python3 "$HELPERS/vouch_budget.py" debit "$WALLET" --stage any >/dev/null 2>&1; then
            echo "1" >> "$SUCC_FILE"
        fi
    ) &
done
wait

success_count=$(wc -l < "$SUCC_FILE" | tr -d ' ')
balance=$(python3 "$HELPERS/vouch_budget.py" show "$WALLET" | python3 -c 'import sys,json; print(json.load(sys.stdin)["balance"])')

if [[ "$success_count" != "$N" ]]; then
    echo "FAIL: success_count=$success_count (expected $N) — atomic debit broken" >&2
    exit 1
fi
if [[ "$balance" != "0" ]]; then
    echo "FAIL: balance=$balance (expected 0)" >&2
    exit 1
fi

echo "OK: scenario_concurrent_debit — $success_count of $ATTEMPTS attempts succeeded, balance=0"
