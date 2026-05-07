#!/usr/bin/env bash
# Scenario 7 — resume after a failed phase.
#
# Run a 3-stage pipeline. Mid-way, simulate stage 2 failing. Then "resume"
# (reset failed phases to pending), retry, finish completed.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"

PROJECT=$(mktemp -d -t vouch-resume-XXXXXX)
trap "rm -rf $PROJECT" EXIT
RUN_DIR="$PROJECT/.vouch/runs/r1"

python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" \
    --phase a:30 --phase b:40 --phase c:30 --id r1 >/dev/null

# Phase a — succeeds
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase a --status running >/dev/null
echo '{"ok":true}' > "$RUN_DIR/a.result.json"
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase a --status completed \
    --result-file "$RUN_DIR/a.result.json" >/dev/null

# Phase b — fails
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase b --status running >/dev/null
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase b --status failed \
    --error "transient API 503" >/dev/null
python3 "$HELPERS/vouch_state.py" finish "$RUN_DIR" --status failed --error "phase b failed" >/dev/null

# Snapshot pre-resume
status_before=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
b_status_before=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["phases"]["b"]["status"])')

if [[ "$status_before" != "failed" ]]; then echo "FAIL: status_before=$status_before" >&2; exit 1; fi
if [[ "$b_status_before" != "failed" ]]; then echo "FAIL: b_status_before=$b_status_before" >&2; exit 1; fi

# === RESUME === reset b and c (c was untouched) to pending; retry both
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase b --status pending >/dev/null

# Phase b — succeeds this time
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase b --status running >/dev/null
echo '{"ok":true,"retry":true}' > "$RUN_DIR/b.result.json"
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase b --status completed \
    --result-file "$RUN_DIR/b.result.json" >/dev/null

# Phase c — succeeds
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase c --status running >/dev/null
echo '{"ok":true}' > "$RUN_DIR/c.result.json"
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase c --status completed \
    --result-file "$RUN_DIR/c.result.json" >/dev/null

python3 "$HELPERS/vouch_state.py" finish "$RUN_DIR" --status completed >/dev/null

# Verify final state
final_status=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
b_final=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["phases"]["b"]["status"])')
b_result=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["phases"]["b"]["result"]["retry"])')

if [[ "$final_status" != "completed" ]]; then echo "FAIL: final_status=$final_status" >&2; exit 1; fi
if [[ "$b_final" != "completed" ]]; then echo "FAIL: b_final=$b_final" >&2; exit 1; fi
if [[ "$b_result" != "True" ]]; then echo "FAIL: b retry result not present (got $b_result)" >&2; exit 1; fi

echo "OK: scenario_resume — failed→reset→retried→completed (b.retry=True)"
