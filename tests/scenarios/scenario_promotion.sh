#!/usr/bin/env bash
# Scenario 5 — tournament promotion (positive case + α-blocked case).

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"
EX="$ROOT/examples/prompt-promotion"

PROJECT=$(mktemp -d -t vouch-promote-XXXXXX)
trap "rm -rf $PROJECT" EXIT

# --- Case 1: judges agree, v2 wins decisively, α high → promoted -----
RES1=$(python3 "$HELPERS/vouch_tournament.py" run "$EX/tournament.json" --out "$PROJECT/r1.json")
winner=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r1.json"))["winner"])')
promoted=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r1.json"))["promoted"])')
alpha=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r1.json"))["alpha"])')
margin=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r1.json"))["margin"])')

if [[ "$winner" != "v2" ]]; then echo "FAIL[case1]: winner=$winner (expected v2)" >&2; exit 1; fi
if [[ "$promoted" != "True" ]]; then echo "FAIL[case1]: promoted=$promoted" >&2; exit 1; fi

# --- Case 2: introduce a contradicting judge → α drops → not promoted -
python3 - <<EOF > "$PROJECT/contested.json"
import json
spec = json.load(open("$EX/tournament.json"))
spec["alpha_threshold"] = 0.667
# Add 3 contradicting verdicts in the llm round (one for each pair)
spec["rounds"][1]["matches"].extend([
    {"a": "v1", "b": "v2", "judge": "anti-quality", "winner": "a", "rationale": "contradicts"},
    {"a": "v1", "b": "v3", "judge": "anti-quality", "winner": "b", "rationale": "contradicts"},
    {"a": "v2", "b": "v3", "judge": "anti-quality", "winner": "b", "rationale": "contradicts"}
])
print(json.dumps(spec))
EOF

python3 "$HELPERS/vouch_tournament.py" run "$PROJECT/contested.json" --out "$PROJECT/r2.json" >/dev/null
promoted2=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r2.json"))["promoted"])')
alpha2=$(python3 -c 'import sys,json; print(json.load(open("'"$PROJECT"'/r2.json"))["alpha"])')

if [[ "$promoted2" != "False" ]]; then
    echo "FAIL[case2]: promoted=$promoted2 (expected False — judges disagree)" >&2
    exit 1
fi

echo "OK: scenario_promotion"
echo "    case1: winner=$winner alpha=$alpha margin=$margin promoted=$promoted"
echo "    case2 (contested): alpha=$alpha2 promoted=$promoted2 (α gate blocked promotion)"
