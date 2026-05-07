---
name: vouch-witness
description: Evaluate a target document against a markdown checklist. Produces a witness report with per-section pass/fail, severity-weighted score, and follow-up questions sourced from the markdown — not from code. Useful for intake quality, document audits, agent-output completeness checks.
---

You are the witness skill. Markdown checklist + JSON target → witness report.

## Argument

`/vouch-witness <checklist.md> <checks.json> <target.json> [--out report.json]`

- `checklist.md` — H2 sections, each with a pipe-table of `| Question | Expected |` rows
- `checks.json` — array of runtime checks; each links to a section + field index
- `target.json` — the document being evaluated (any JSON object)

## Step 1 — Validate inputs

- `checklist.md` exists and parses to ≥1 section
- `checks.json` is an array; each item has `id`, `severity`, `detect`
- `target.json` is a JSON object

If any fails, print the specific error and stop.

## Step 2 — Run the helper

```bash
python3 $PLUGIN_DIR/helpers/vouch_witness.py evaluate \
    <checklist.md> <checks.json> <target.json> \
    --out <out_path>
```

The helper handles all five built-in detect kinds (`field_present`, `field_equals`, `regex`, `contains_keyword`, `custom`) and uses the SEVERITY_WEIGHTS table internally.

## Step 3 — Render the report

Read the helper output. Print:

```
score          : 0.xx  (good | acceptable | poor)
checks         : passed=N, failed=M, total=K

Follow-up questions:
  [critical] {followup_question}
  [high    ] {followup_question}
  [medium  ] {followup_question}
  [low     ] {followup_question}
```

If `gaps` is empty, print `No gaps. ✓`.

## Step 4 — Optional escalation

If `label` is `"poor"` and the user has a Slack/Linear/email integration available (offered via MCP), ask whether to send the follow-up questions to a named owner. Do NOT send proactively.

## Why the markdown matters

The follow-up question text comes from `checklist.md`. Editors update the markdown; the report wording follows on the next run. Code reviewers don't have to read prose; PMs don't have to read code.

When you run this skill twice with different checklists pointing at the same target, you get different follow-up wording without changing any Python or any check definitions — that's the design.

## Rules

- Never invent follow-up questions. If a check has no `template_field_idx`, the helper falls back to `"<label>?"` — that's fine; don't paper over it with a richer question.
- Do not modify `checks.json` or `checklist.md`.
- If the user asks "why did X fail?", read the specific check's detect block and explain the rule.
