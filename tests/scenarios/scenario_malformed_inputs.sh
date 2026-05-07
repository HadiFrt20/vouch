#!/usr/bin/env bash
# Scenario 10 — helpers reject malformed inputs cleanly.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"

PROJECT=$(mktemp -d -t vouch-malformed-XXXXXX)
trap "rm -rf $PROJECT" EXIT

# --- vouch_state init refuses to overwrite without --force --------------
RUN_DIR="$PROJECT/run1"
python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" --phase a:1 --id r1 >/dev/null
if python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" --phase a:1 --id r1 2>/dev/null; then
    echo "FAIL: state init should refuse to clobber existing without --force" >&2
    exit 1
fi
# --force should succeed
python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" --phase a:1 --id r1 --force >/dev/null

# --- vouch_state update rejects unknown phase ---------------------------
if python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase ghost --status running 2>/dev/null; then
    echo "FAIL: state update should reject unknown phase" >&2
    exit 1
fi

# --- vouch_state update rejects unknown status --------------------------
if python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase a --status banana 2>/dev/null; then
    echo "FAIL: state update should reject unknown status" >&2
    exit 1
fi

# --- vouch_budget refuses negative initial balance ---------------------
if python3 "$HELPERS/vouch_budget.py" init "$PROJECT/bad.json" --balance -5 2>/dev/null; then
    echo "FAIL: budget init should reject negative balance" >&2
    exit 1
fi

# --- vouch_budget debit returns exit 2 on insufficient -----------------
python3 "$HELPERS/vouch_budget.py" init "$PROJECT/wallet.json" --balance 1 \
    --cost-per-stage '{"big":100}' >/dev/null
set +e
python3 "$HELPERS/vouch_budget.py" debit "$PROJECT/wallet.json" --stage big >/dev/null 2>&1
rc=$?
set -e
if [[ $rc -ne 2 ]]; then
    echo "FAIL: insufficient debit should exit 2 (got $rc)" >&2
    exit 1
fi

# --- vouch_tournament rejects spec with <2 candidates ------------------
echo '{"candidates":["v1"],"rounds":[{"name":"r","k":32,"matches":[]}]}' > "$PROJECT/bad-tournament.json"
if python3 "$HELPERS/vouch_tournament.py" run "$PROJECT/bad-tournament.json" 2>/dev/null; then
    echo "FAIL: tournament with 1 candidate should be rejected" >&2
    exit 1
fi

# --- vouch_tournament rejects invalid JSON -----------------------------
echo "not json" > "$PROJECT/notjson"
if python3 "$HELPERS/vouch_tournament.py" run "$PROJECT/notjson" 2>/dev/null; then
    echo "FAIL: tournament should reject non-JSON" >&2
    exit 1
fi

# --- vouch_witness with non-existent template ---------------------------
echo "[]" > "$PROJECT/empty-checks.json"
echo "{}" > "$PROJECT/empty-target.json"
if python3 "$HELPERS/vouch_witness.py" evaluate \
    "$PROJECT/missing.md" "$PROJECT/empty-checks.json" "$PROJECT/empty-target.json" \
    2>/dev/null; then
    echo "FAIL: witness should fail on missing template" >&2
    exit 1
fi

echo "OK: scenario_malformed_inputs — all 7 invalid inputs rejected with non-zero exit"
