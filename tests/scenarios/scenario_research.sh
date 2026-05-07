#!/usr/bin/env bash
# Scenario 4 — full research pipeline with adversary verification.
#
# Drives examples/research-pipeline/ end-to-end. Simulates what the
# vouch-stage and vouch-adversary subagents would write. Verifies the
# adversary verdicts attach correctly and survival arithmetic is right.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"
HELPERS="$ROOT/helpers"
EXAMPLE="$ROOT/examples/research-pipeline"

PROJECT=$(mktemp -d -t vouch-research-XXXXXX)
trap "rm -rf $PROJECT" EXIT
RUN_DIR="$PROJECT/.vouch/runs/r1"

# Init from the example pipeline.md
python3 "$HELPERS/vouch_state.py" init "$RUN_DIR" \
    --pipeline "$EXAMPLE/pipeline.md" --id r1 >/dev/null

# Stage 1: fetch
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase fetch --status running >/dev/null
python3 -c "
import json
corpus = json.load(open('$EXAMPLE/corpus.json'))
out = {'passages': [{'doc_id': k, 'text': v} for k, v in corpus.items()]}
print(json.dumps(out))
" > "$RUN_DIR/fetch.result.json"
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase fetch --status completed \
    --result-file "$RUN_DIR/fetch.result.json" >/dev/null

# Stage 2: extract — produce 3 claims as a top-level list (stage-protocol.md shape #3)
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase extract --status running >/dev/null
cat > "$RUN_DIR/extract.result.json" <<'EOF'
[
  {"text": "Ada Lovelace was born in 1815.", "confidence": 0.85},
  {"text": "Ada Lovelace was the first programmer.", "confidence": 0.70},
  {"text": "Lovelace founded the Analytical Engine company.", "confidence": 0.40}
]
EOF
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase extract --status completed \
    --result-file "$RUN_DIR/extract.result.json" >/dev/null

# Adversary pass — what vouch-adversary would produce against the corpus.
# Two confirmed (with quotes), one weakened.
cat > "$RUN_DIR/extract.adversary.json" <<'EOF'
[
  {
    "text": "Ada Lovelace was born in 1815.",
    "confidence": 0.85,
    "verdict": "confirmed",
    "confidence_delta": 0.0,
    "adversary_evidence": "doc_a contains 'Ada Lovelace was born in 1815'",
    "verification_mode": "source_verification",
    "quote": "Ada Lovelace was born in 1815 in London.",
    "source_url": "corpus://doc_a"
  },
  {
    "text": "Ada Lovelace was the first programmer.",
    "confidence": 0.70,
    "verdict": "confirmed",
    "confidence_delta": 0.0,
    "adversary_evidence": "doc_a calls her 'first computer programmer'",
    "verification_mode": "source_verification",
    "quote": "She is widely regarded as the first computer programmer",
    "source_url": "corpus://doc_a"
  },
  {
    "text": "Lovelace founded the Analytical Engine company.",
    "confidence": 0.40,
    "verdict": "weakened",
    "confidence_delta": -0.20,
    "adversary_evidence": "no source mentions Lovelace founding any company",
    "verification_mode": "cross_reference",
    "quote": "The Analytical Engine, designed in the 1830s, was never completed during Babbage's lifetime.",
    "source_url": "corpus://doc_b"
  }
]
EOF

# Stage 3: synthesize — uses surviving claims (survival_score >= 0.5)
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase synthesize --status running >/dev/null
python3 - <<EOF > "$RUN_DIR/synthesize.result.json"
import json
claims = json.load(open("$RUN_DIR/extract.adversary.json"))
def survival(c):
    v, conf, delta = c["verdict"], c["confidence"], c.get("confidence_delta", 0.0)
    if v == "confirmed":    return conf
    if v == "weakened":     return max(0.0, conf + delta)
    if v == "refuted":      return 0.0
    if v == "unverifiable": return conf * 0.5
    return conf
surviving = [c for c in claims if survival(c) >= 0.5]
out = {"summary": " ".join(c["text"] for c in surviving),
       "n_used": len(surviving), "n_dropped": len(claims) - len(surviving)}
print(json.dumps(out))
EOF
python3 "$HELPERS/vouch_state.py" update "$RUN_DIR" --phase synthesize --status completed \
    --result-file "$RUN_DIR/synthesize.result.json" >/dev/null

python3 "$HELPERS/vouch_state.py" finish "$RUN_DIR" --status completed >/dev/null

# Verify
n_confirmed=$(python3 -c '
import json
claims = json.load(open("'"$RUN_DIR"'/extract.adversary.json"))
print(sum(1 for c in claims if c["verdict"] == "confirmed"))
')
n_weakened=$(python3 -c '
import json
claims = json.load(open("'"$RUN_DIR"'/extract.adversary.json"))
print(sum(1 for c in claims if c["verdict"] == "weakened"))
')
n_used=$(python3 -c '
import json
print(json.load(open("'"$RUN_DIR"'/synthesize.result.json"))["n_used"])
')
status=$(python3 "$HELPERS/vouch_state.py" read "$RUN_DIR" | python3 -c 'import sys,json; print(json.load(sys.stdin)["status"])')

if [[ "$n_confirmed" != "2" ]]; then echo "FAIL: confirmed=$n_confirmed (expected 2)" >&2; exit 1; fi
if [[ "$n_weakened" != "1" ]]; then echo "FAIL: weakened=$n_weakened (expected 1)" >&2; exit 1; fi
if [[ "$n_used" != "2" ]]; then echo "FAIL: synthesis used $n_used claims (expected 2 — the weakened one's survival score is 0.20)" >&2; exit 1; fi
if [[ "$status" != "completed" ]]; then echo "FAIL: status=$status" >&2; exit 1; fi

echo "OK: scenario_research — confirmed=$n_confirmed weakened=$n_weakened used=$n_used run=$status"
