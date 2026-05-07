---
name: vouch-init
description: Scaffold a new vouch pipeline project — interview-style. Produces pipeline.md describing stages, optional budget.json wallet, optional checklist.md witness template, and an initial state file. Use this BEFORE /vouch-run.
---

You are scaffolding a new vouch pipeline. Walk the user through 4–6 questions, then write the project files.

## Step 1 — Locate the project

Ask the user where the pipeline should live (default: `./vouch-pipeline/`). Create the directory.

## Step 2 — Interview

Use the `AskUserQuestion` tool. Required answers:

1. **Pipeline name** — short kebab-case. Used as the run-directory prefix.
2. **Stages** — 2–6 ordered stages. For each stage collect:
   - `name` (kebab-case)
   - `weight` (1–100, contributes to progress %)
   - one-line description of what the stage does
3. **Verification needed?** — yes/no. If yes, also ask which adversary modes apply (any subset of `source_verification`, `contradiction_search`, `cross_reference`, `temporal_check`).
4. **Budget needed?** — yes/no. If yes, ask for an integer initial balance plus per-stage cost (a single int or per-stage map).
5. **Witness checklist needed?** — yes/no. If yes, ask the user to draft 1–3 markdown sections of fields (or skip and let them edit `checklist.md` later).

## Step 3 — Write `pipeline.md`

Produce a file in this exact shape:

```markdown
# {pipeline name}

{one-paragraph description, written by you from the user's answers}

## Stages

- name: {stage1}
  weight: {n}
  description: {one-line}
- name: {stage2}
  weight: {n}
  description: {one-line}

## Verification

modes: [{...}]   # only if user said yes

## Budget

initial: {int}
cost_per_stage: {int or map}   # only if user said yes
```

The `vouch_state.py init` helper parses the `## Stages` block. Do not omit `name:` or `weight:` lines.

## Step 4 — Initialise state

Create the runs directory and seed state by shelling out to the helper:

```bash
mkdir -p {project_dir}/.vouch/runs/{run_id}
python3 {plugin_dir}/helpers/vouch_state.py init \
    {project_dir}/.vouch/runs/{run_id} \
    --pipeline {project_dir}/pipeline.md \
    --metadata '{"pipeline_name":"{name}"}'
```

The helper prints `{id, run_dir, phases}`. Echo the run_id back to the user.

## Step 5 — Optional artifacts

If the user requested:

- **Budget**: `python3 {plugin_dir}/helpers/vouch_budget.py init {project_dir}/.vouch/budget.json --balance N --cost-per-stage '{...}'`
- **Witness checklist**: write `{project_dir}/checklist.md` and `{project_dir}/checks.json` from the user's draft. The `checks.json` shape is documented in `helpers/vouch_witness.py`.

## Step 6 — Print the next step

End with:

```
Next:
  /vouch-run {project_dir}
  /vouch-status {project_dir}
```

## Rules

- Never invent stages the user didn't confirm.
- Always validate `weight` is a positive integer.
- Reject pipeline names with spaces or shell-special characters.
- If the directory exists and is non-empty, refuse and ask the user to clear it or pick another path.
