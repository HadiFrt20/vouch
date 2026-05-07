# Intake checklist

Markdown-driven witness graph. The follow-up question text lives in
`checklist.md`; the runtime checks in `checks.json` reference fields by
section + index. Edit the markdown, the wording updates next run.

## Run it (driver, no Claude)

```bash
# Good intake — should score 1.0 (good)
python3 ../../helpers/vouch_witness.py evaluate \
    checklist.md checks.json sample-good.json

# Weak intake — should score 0.0 (poor) with 5 follow-up questions
python3 ../../helpers/vouch_witness.py evaluate \
    checklist.md checks.json sample-weak.json
```

## Edit the wording, see it propagate

Open `checklist.md`. Change `Who feels the pain today?` to
`Whose KPI is moving when this lands?`. Re-run on `sample-weak.json`. The
"high"-severity follow-up question now uses your new wording — no code change.

That's the design. Detection is code; remediation is markdown.
