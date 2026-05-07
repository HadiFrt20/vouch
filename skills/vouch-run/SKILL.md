---
name: vouch-run
description: Execute a vouch pipeline by running stages sequentially, debiting the budget per stage, spawning the vouch-stage subagent for the work, and optionally calling vouch-adversary on any Claim objects in the result. Reads pipeline.md from the project directory; mutates state.json after each transition. Idempotent — re-running picks up where state left off.
---

You are the vouch loop runner. Read state, run the next pending stage, repeat until done.

## Argument

`/vouch-run <project_dir>` — the directory containing `pipeline.md`. If omitted, default to `./`.

## Step 0 — Resolve paths

Compute these once and reuse:

```
PLUGIN_DIR   = directory containing this skill
PROJECT_DIR  = arg or "./"
PIPELINE     = $PROJECT_DIR/pipeline.md
RUNS_DIR     = $PROJECT_DIR/.vouch/runs
BUDGET       = $PROJECT_DIR/.vouch/budget.json    (optional)
HELPERS      = $PLUGIN_DIR/helpers
```

If `pipeline.md` is missing, tell the user to run `/vouch-init` first.

## Step 1 — Find or create the active run

Look for an existing run in `$RUNS_DIR/*/state.json` whose status is `pending` or `running`. If found, use it. If not, create a new one:

```bash
RUN_ID=$(uuidgen | tr -d - | cut -c1-12)
mkdir -p $RUNS_DIR/$RUN_ID
python3 $HELPERS/vouch_state.py init $RUNS_DIR/$RUN_ID --pipeline $PIPELINE
```

Set `RUN_DIR=$RUNS_DIR/$RUN_ID`.

## Step 2 — Read state, find the next pending phase

```bash
python3 $HELPERS/vouch_state.py read $RUN_DIR
```

Parse the JSON. Find the first phase with `status == "pending"`. If none, jump to Step 6 (finish).

Let `PHASE = the next pending phase name`.

## Step 3 — Budget gate

If `$BUDGET` exists, debit before running:

```bash
python3 $HELPERS/vouch_budget.py debit $BUDGET --stage $PHASE
```

- Exit 0 → debited; proceed.
- Exit 2 → insufficient. Mark the phase `skipped` with error `"budget exhausted"`, finish the run as `failed`, and stop.

```bash
python3 $HELPERS/vouch_state.py update $RUN_DIR --phase $PHASE --status skipped --error "budget exhausted"
python3 $HELPERS/vouch_state.py finish $RUN_DIR --status failed --error "budget exhausted at $PHASE"
```

## Step 4 — Run the phase

Mark `running`:

```bash
python3 $HELPERS/vouch_state.py update $RUN_DIR --phase $PHASE --status running
```

Spawn the `vouch-stage` subagent (use the Agent tool with `subagent_type: "vouch-stage"`) and pass it:

- `project_dir`
- `run_dir`
- `phase` (name)
- the section of `pipeline.md` describing this stage
- prior-phase results (read from `state.json`)

The subagent must write its result as JSON to `$RUN_DIR/$PHASE.result.json`. After it returns:

```bash
python3 $HELPERS/vouch_state.py update $RUN_DIR --phase $PHASE --status completed --result-file $RUN_DIR/$PHASE.result.json
```

If the subagent reports a failure (returns an error envelope), mark the phase `failed` instead and stop the run unless the stage was declared `on_error: skip` in `pipeline.md`.

## Step 5 — Adversary hook (if pipeline.md declares verification)

If the pipeline has a `## Verification` block AND the result contains a top-level `claims` array (or is itself an array of objects with `text` keys), spawn `vouch-adversary` to verify. Pass:

- `claims_file` = `$RUN_DIR/$PHASE.result.json`
- `modes` = the modes from pipeline.md
- `out_file` = `$RUN_DIR/$PHASE.adversary.json`

Append the verified claims to `state.metadata.adversary[$PHASE]` by reading state, mutating, and writing via `update` (or directly via the helper if you extend it).

## Step 6 — Loop or finish

After Step 4/5, go back to Step 2. When all phases are terminal (`completed`, `failed`, or `skipped`):

```bash
python3 $HELPERS/vouch_state.py finish $RUN_DIR --status completed
```

(or `failed` if any phase failed and `on_error` was `fail`).

## Step 7 — Report

Print a compact summary:

```
run_id      : <RUN_ID>
status      : <STATUS>
progress    : <pct>%
phases      : completed=N, failed=N, skipped=N
artifacts   : $RUN_DIR/
budget      : balance=N (spent=M)   (if budget present)
```

## Rules

- Always re-read state after every helper call. Do not cache.
- If the run is already `completed` or `failed` when you start, refuse to advance and tell the user to clear `$RUN_DIR` or use `/vouch-resume` (a resume re-runs failed phases; a fresh run is always a fresh `RUN_ID`).
- Stage `fn` execution lives in the `vouch-stage` subagent — never run user-supplied code inline in this skill.
- Subagent failures are not skill failures: capture the error, mark the phase, and continue per `on_error` policy.
