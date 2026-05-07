---
name: vouch-status
description: Print a compact status dashboard for a vouch project — current run progress, phase breakdown, last-N runs, budget balance, latest adversary survival rate. Useful at any point during or after a run.
---

You are the status dashboard. Read state and print a clear summary. Side-effect free.

## Argument

`/vouch-status <project_dir>` — default `./`.

## Step 1 — Resolve

```
PROJECT_DIR  = arg or "./"
RUNS_DIR     = $PROJECT_DIR/.vouch/runs
BUDGET       = $PROJECT_DIR/.vouch/budget.json    (optional)
REGISTRY_DIR = $PROJECT_DIR/.vouch/registry        (optional)
```

If `RUNS_DIR` doesn't exist, tell the user this isn't a vouch project (no `/vouch-init` has been run).

## Step 2 — Most recent run

Find the most recently modified `state.json` under `$RUNS_DIR/`. Read it via:

```bash
python3 $PLUGIN_DIR/helpers/vouch_state.py read $RUNS_DIR/<run_id>
```

## Step 3 — Compute the dashboard

From the state JSON, derive:

- run id
- overall status & progress %
- per-phase one-liner: `name  weight  status  duration`
- if `metadata.adversary` exists for any phase, compute survival_rate over those claims (see /vouch-verify rules)
- budget balance (read $BUDGET if present)
- registry aliases per name (read each `_index.json` if registry exists)

## Step 4 — Render

```
Project        : {PROJECT_DIR}
─────────────────────────────────────────────
Active run     : {run_id}
Status         : running 60%

Phases:
  fetch        weight 20  ✓ completed   1.2s
  classify     weight 40  ⏵ running    
  recommend    weight 40  · pending    

Adversary (claims so far):
  classify     5 claims   2 confirmed, 1 weakened, 1 refuted, 1 unverifiable
                          survival_rate=0.75   trust_score=0.56

Budget:
  balance=42 (initial=100, spent=58)

Registry:
  summarizer   @candidate=v3   @production=v2
─────────────────────────────────────────────
Recent runs    (5 most recent):
  20260507a3f1  completed  100%  2026-05-07T09:12Z
  20260506b1e2  failed      40%  2026-05-06T18:44Z (budget exhausted at recommend)
  ...
```

Use ASCII status icons consistently:
- `✓` completed
- `⏵` running
- `·` pending
- `↷` skipped
- `✗` failed

## Step 5 — Suggest next steps

Conditional one-liners:

- If status is `running`: `(another /vouch-run will pick up where it left off)`
- If status is `failed` and last error was budget: `(top up via vouch_budget.py credit, then /vouch-run)`
- If status is `failed` for another reason: `(/vouch-resume to retry failed phases)`
- If status is `completed`: `(check artifacts at $RUN_DIR/)`

## Rules

- Never mutate state. Read-only.
- If the runs dir has 0 entries, suggest `/vouch-run` to start.
- If the most recent run is older than 7 days, mention it explicitly so the user knows the dashboard isn't fresh.
