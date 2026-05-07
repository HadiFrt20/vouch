---
name: vouch-promote
description: Tournament-gate ANY change to a Claude Code artifact. Candidates can be prompts, SKILL.md files, subagent definitions, MCP/settings configs, hooks, agent flows, full pipeline.md files — anything you'd alias as @production. Spawns the vouch-judge subagent per judge per round, computes ELO + Krippendorff α, and updates the registry alias only when margin AND α both clear.
---

You are the promotion gate. Two artifacts go in; one alias update or zero comes out.

**Candidates are not just prompts.** They can be:
- prompt files (`.md` or string)
- SKILL.md files (one skill's instructions vs another)
- subagent definitions (alternative `agents/*.md` files)
- MCP server configs / `settings.json` variants
- hook configurations
- whole `pipeline.md` files (one pipeline shape vs another)
- arbitrary text or JSON the judges know how to compare

Use this whenever you'd otherwise *guess* which version is better.

## Argument

`/vouch-promote <tournament_spec.md>`

The spec describes:

- candidates (paths or inline content)
- a registry name (e.g. `summarizer`)
- rounds (cheap → llm → cross), each with judges and a K
- promotion thresholds (margin, optional alpha)

Example shape (markdown with embedded YAML-ish blocks):

```markdown
# Tournament: summarizer-v3-vs-v4

## Candidates

- id: v3
  path: prompts/summarizer-v3.md
- id: v4
  path: prompts/summarizer-v4.md

## Registry

name: summarizer

## Rounds

- name: cheap
  k: 32
  judges: [length-check, structure-check]
- name: llm
  k: 24
  judges: [llm-quality]
- name: cross
  k: 16
  judges: [cross-vendor-quality]

## Gate

promotion_margin: 50
alpha_threshold: 0.667
```

## Step 1 — Parse the spec

Read the spec file. Validate:

- ≥2 candidates, with non-empty `id` and either `path` or inline `content`
- ≥1 round, each with ≥1 judge name and a positive K
- `promotion_margin` is a non-negative number; `alpha_threshold` is None or in [-1, 1]

## Step 2 — Run all matches

For each round, for each unordered pair `(a, b)` of candidates, for each judge:

Spawn the `vouch-judge` subagent. Pass it:

- the two candidates
- the judge name (the subagent's prompt determines what that judge looks at)
- a fresh tmp file path for the verdict

Each subagent writes a JSON object: `{"a": id, "b": id, "judge": name, "winner": "a"|"b"|"draw", "rationale": "..."}`.

Collect all match objects. Group by round.

## Step 3 — Compute ELO + α

Write a verdict file at `$TMP/tournament.json`:

```json
{
  "candidates": ["v3", "v4"],
  "starting_rating": 1200,
  "promotion_margin": 50,
  "alpha_threshold": 0.667,
  "rounds": [
    {"name": "cheap", "k": 32, "matches": [...]},
    {"name": "llm",   "k": 24, "matches": [...]},
    {"name": "cross", "k": 16, "matches": [...]}
  ]
}
```

Run:

```bash
python3 $PLUGIN_DIR/helpers/vouch_tournament.py run $TMP/tournament.json --out $TMP/result.json
```

The helper prints `{standings, winner, alpha, margin, promoted, history}`.

## Step 4 — Apply the gate

Read `result.json`. Promotion requires BOTH:

- `margin >= promotion_margin`
- `alpha >= alpha_threshold` (skipped if `alpha_threshold` is null)

`vouch_tournament.py` already computes `promoted` correctly — trust its boolean.

## Step 5 — Update the registry

Registry path: `$PROJECT_DIR/.vouch/registry/<name>/`. Each candidate is registered as a new version (numbered v1, v2, ...). The `_index.json` tracks versions and aliases.

Logic:

1. For every candidate that isn't already in the registry, register it (write `v{N}.json` and update `_index.json`).
2. Always set `<name>@candidate` to the winner.
3. If `result.promoted` is true, also set `<name>@production` to the winner.

You can implement this inline in bash + jq, or by reading/writing the JSON files directly. The aliases dict is just `{alias: version_id}`.

## Step 6 — Print the report

```
tournament   : <spec name>
candidates   : v1, v2, v3
winner       : v2
margin       : 101.2 (need ≥ 50)
α            : 0.83 (need ≥ 0.667)
promoted     : YES
alias updated: summarizer@production → v2 (was v1)
```

If not promoted:

```
promoted     : NO  (margin OK but α=0.42 below 0.667)
alias updated: summarizer@candidate → v2 (production unchanged)
```

## Rules

- Never promote without running ALL configured judges in ALL configured rounds.
- A judge that crashes is recorded as `winner: null`; do NOT treat that as a draw — α handles missing data, ELO doesn't update for null winners.
- The tournament helper handles α correctly when judges are missing some matches; you don't have to special-case it.
- If margin and α both pass but the user passed `--dry-run`, print the would-be alias updates and exit without writing.
