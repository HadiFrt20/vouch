#!/usr/bin/env bash
# Scenario 8 — vouch_state.py init parses pipeline.md correctly.
#
# Specifically: stages must be picked up in order; weights must be ints;
# extra YAML lines like `description:` are ignored gracefully.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"
EX="$ROOT/examples/research-pipeline"

PROJECT=$(mktemp -d -t vouch-parse-XXXXXX)
trap "rm -rf $PROJECT" EXIT
RUN_DIR="$PROJECT/.vouch/runs/r1"

python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" \
    --pipeline "$EX/pipeline.md" --id r1 >/dev/null

phases=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(",".join(d["phases"].keys()))
')

weights=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c '
import sys, json
d = json.load(sys.stdin)
print(",".join(str(p["weight"]) for p in d["phases"].values()))
')

if [[ "$phases" != "fetch,extract,synthesize" ]]; then
    echo "FAIL: phases=$phases (expected fetch,extract,synthesize)" >&2
    exit 1
fi
if [[ "$weights" != "10,50,40" ]]; then
    echo "FAIL: weights=$weights (expected 10,50,40)" >&2
    exit 1
fi

echo "OK: scenario_pipeline_md_parse — phases=$phases weights=$weights"
