#!/usr/bin/env bash
# Scenario 6 — witness checklist with template_field_idx remediation.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"
EX="$ROOT/examples/intake-checklist"

PROJECT=$(mktemp -d -t vouch-witness-XXXXXX)
trap "rm -rf $PROJECT" EXIT

# --- Good intake should pass with no gaps ------------------------------
python3 "$HELPERS/vouch_witness.py" evaluate \
    "$EX/checklist.md" "$EX/checks.json" "$EX/sample-good.json" \
    --out "$PROJECT/good.json" >/dev/null

label=$(python3 -c 'import json; print(json.load(open("'"$PROJECT"'/good.json"))["label"])')
score=$(python3 -c 'import json; print(json.load(open("'"$PROJECT"'/good.json"))["overall_score"])')
n_gaps=$(python3 -c 'import json; print(len(json.load(open("'"$PROJECT"'/good.json"))["gaps"]))')

if [[ "$label" != "good" ]]; then echo "FAIL: label=$label (expected good)" >&2; exit 1; fi
if [[ "$n_gaps" != "0" ]]; then echo "FAIL: n_gaps=$n_gaps (expected 0)" >&2; exit 1; fi

# --- Weak intake should produce 5 gaps with template-sourced followups -
python3 "$HELPERS/vouch_witness.py" evaluate \
    "$EX/checklist.md" "$EX/checks.json" "$EX/sample-weak.json" \
    --out "$PROJECT/weak.json" >/dev/null

weak_label=$(python3 -c 'import json; print(json.load(open("'"$PROJECT"'/weak.json"))["label"])')
weak_gaps=$(python3 -c 'import json; print(len(json.load(open("'"$PROJECT"'/weak.json"))["gaps"]))')
# Look up the pain_owner gap by id — the markdown row "role / team" feeds it
pain_owner_followup=$(python3 -c '
import json
gaps = json.load(open("'"$PROJECT"'/weak.json"))["gaps"]
m = next((g for g in gaps if g["id"] == "pain_owner"), None)
print(m["followup_question"] if m else "")
')

if [[ "$weak_label" != "poor" ]]; then echo "FAIL: weak_label=$weak_label" >&2; exit 1; fi
if [[ "$weak_gaps" -lt "4" ]]; then echo "FAIL: weak_gaps=$weak_gaps (expected ≥4)" >&2; exit 1; fi
if ! [[ "$pain_owner_followup" == *"role / team"* ]]; then
    echo "FAIL: pain_owner follow-up doesn't include the markdown's 'role / team' hint" >&2
    echo "      got: $pain_owner_followup" >&2
    exit 1
fi

# --- Edit the markdown, the next run uses new wording -----------------
TMPL_COPY="$PROJECT/checklist.md"
sed 's|Who feels the pain today?|Whose KPI is moving when this lands?|' \
    "$EX/checklist.md" > "$TMPL_COPY"

python3 "$HELPERS/vouch_witness.py" evaluate \
    "$TMPL_COPY" "$EX/checks.json" "$EX/sample-weak.json" \
    --out "$PROJECT/weak2.json" >/dev/null

new_followup=$(python3 -c 'import json
gaps = json.load(open("'"$PROJECT"'/weak2.json"))["gaps"]
match = next((g for g in gaps if g["id"] == "pain_owner"), None)
print(match["followup_question"] if match else "")
')

if ! [[ "$new_followup" == *"KPI is moving"* ]]; then
    echo "FAIL: edited template did not propagate to follow-up" >&2
    echo "      got: $new_followup" >&2
    exit 1
fi

echo "OK: scenario_witness — good=$label/$score weak=$weak_label/${weak_gaps} template_edit=propagated"
