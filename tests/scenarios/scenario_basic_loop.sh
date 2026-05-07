#!/usr/bin/env bash
# Scenario 1 — basic loop without adversary or budget.
#
# Simulates what /vouch-run would do when the pipeline.md has no
# Verification or Budget block. Each "stage" here is just a JSON write
# (in real use, it'd be a vouch-stage subagent invocation).
#
# Pass: all phases reach `completed`; progress = 100%; state shape valid.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"

# Fresh project dir
PROJECT=$(mktemp -d -t vouch-basic-XXXXXX)
trap "rm -rf $PROJECT" EXIT
RUN_DIR="$PROJECT/.vouch/runs/r1"

# 1. Init pipeline (use --phase shorthand to skip pipeline.md parsing)
python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" \
    --phase fetch:20 --phase transform:30 --phase load:50 \
    --id r1 --metadata '{"scenario":"basic"}' >/dev/null

# 2. Run each stage in sequence
for stage in fetch transform load; do
    python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase "$stage" --status running >/dev/null
    echo "{\"stage\":\"$stage\",\"ok\":true}" > "$RUN_DIR/$stage.result.json"
    python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase "$stage" --status completed \
        --result-file "$RUN_DIR/$stage.result.json" >/dev/null
done

# 3. Finish
python3 "$HELPERS/vouch_state.py" finish "$RUN_DIR" --status completed >/dev/null

# 4. Verify
RESULT=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR")
status=$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')
progress=$(echo "$RESULT" | python3 -c 'import sys,json; print(json.load(sys.stdin)["progress_pct"])')
phases_done=$(echo "$RESULT" | python3 -c '
import sys,json
d = json.load(sys.stdin)
print(sum(1 for p in d["phases"].values() if p["status"]=="completed"))
')

if [[ "$status" != "completed" ]]; then echo "FAIL: status=$status (expected completed)" >&2; exit 1; fi
if [[ "$progress" != "100.0" ]]; then echo "FAIL: progress=$progress" >&2; exit 1; fi
if [[ "$phases_done" != "3" ]]; then echo "FAIL: phases_done=$phases_done" >&2; exit 1; fi

echo "OK: scenario_basic_loop — status=$status progress=$progress phases_done=$phases_done"
