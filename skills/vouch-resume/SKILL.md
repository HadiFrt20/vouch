---
name: vouch-resume
description: Resume a failed or interrupted vouch run. Re-runs phases that are in failed/skipped state without disturbing completed phases. Useful after a crash, after topping up the budget, or after fixing whatever caused a stage to fail.
---

You are the resume skill. Pick up exactly where state left off; don't redo work that already finished.

## Argument

`/vouch-resume <project_dir> [<run_id>]`

If `run_id` is omitted, target the most recently modified run under `$PROJECT_DIR/.vouch/runs/`.

## Step 1 — Locate the run

If `run_id` is given, require `$PROJECT_DIR/.vouch/runs/<run_id>/state.json` to exist. If not, error out and list available run ids.

## Step 2 — Inspect state

```bash
python3 $PLUGIN_DIR/helpers/vouch_state.py read $RUN_DIR
```

Expected outcomes:

- All phases `completed` → tell the user "nothing to resume" and stop.
- Run-level status `completed` but a phase is `failed` → unusual; warn the user.
- One or more phases `failed` or `skipped` → these are the resume targets.

## Step 3 — Reset target phases

For each phase to resume, transition it from `failed`/`skipped` back to `pending`:

```bash
python3 $PLUGIN_DIR/helpers/vouch_state.py update $RUN_DIR --phase $P --status pending
```

Then transition the run-level status from `failed` back to `running` by re-initialising via update on the first reset phase (the helper auto-bumps run status on first `running` transition).

## Step 4 — Hand off to /vouch-run

Tell the user explicitly:

```
Reset N phase(s) to pending: <list>
Run /vouch-run <project_dir> to continue.
```

Do NOT auto-invoke `/vouch-run`. The user might want to top up the budget or edit the pipeline first.

## Edge cases

- **Budget previously exhausted** — tell the user the budget needs to be topped up before resuming, and show the current balance.
- **Pipeline edited since the run started** — if `pipeline.md` has new stages that aren't in `state.json`, tell the user the safest path is a fresh run (don't try to splice).
- **Adversary sidecar** — leave existing `state.metadata.adversary` entries in place; re-running a phase appends new entries, doesn't overwrite.
- **Budget already debited for a failed phase** — that's fine; we don't refund. Spend is monotone.

## Rules

- Never delete result files. The user might want to inspect what the failed run produced.
- If a phase is `running` (someone left it that way after a crash), treat it as `failed` for resume purposes.
- Refuse if state.json is locked by another process — the lock means a run is actively in flight.
