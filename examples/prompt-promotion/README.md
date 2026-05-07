# Prompt promotion

A tournament between three summariser prompts. Three rounds: cheap heuristic,
LLM-quality, cross-vendor. The `tournament.json` is what `/vouch-promote`
would produce after spawning the `vouch-judge` subagent for each pair × judge.

## Run it (driver, no Claude)

```bash
python3 ../../helpers/vouch_tournament.py run tournament.json
```

## Expected outcome

`v2` wins decisively — ELO ~1300+, margin ≥ 100, α ≈ 1.0, **promoted: true**.

In the full skill flow, the next step writes a registry alias:

```
summarizer@candidate  → v2
summarizer@production → v2   (promoted)
```

## Try blocking promotion

Edit `tournament.json` to add a contradicting judge in the `llm` round:

```json
{"a": "v1", "b": "v2", "judge": "anti-quality", "winner": "a", "rationale": "..."}
```

This drives Krippendorff α down. With `alpha_threshold: 0.5`, the runner will
report `promoted: false` even if v2 still has the highest ELO. That's the
gate doing its job — judges don't agree, don't ship.
