# Tests

Two layers:

1. **Helper protocol scenarios** (`scenarios/scenario_*.sh`) — bash drivers that
   simulate what each skill + subagent would do, but using the helpers directly.
   This is what verifies the plugin's contracts hold without going through
   Claude Code.
2. **Skill prompt review** — manual. Read each `SKILL.md` and verify it
   describes the protocol the helpers expect. The scenarios catch protocol
   drift; reviewing the markdown catches *Claude misreading the protocol*.

## Run all scenarios

```bash
bash tests/scenarios/run_all.sh
```

Expected: 10 passed, 0 failed, ~10 seconds.

## What each scenario covers

| Scenario | Validates |
|---|---|
| `scenario_basic_loop.sh` | Loop progresses through all phases; status transitions; final progress = 100%. |
| `scenario_budget_exhaustion.sh` | Insufficient balance → phase marked `skipped` with reason; run finalises as `failed`. |
| `scenario_concurrent_debit.sh` | 400 parallel debits against a wallet of 200 → exactly 200 succeed, balance → 0. Atomic invariant under contention. |
| `scenario_pipeline_md_parse.sh` | The example `pipeline.md` parses into the right phase ordering and weights. |
| `scenario_promotion.sh` | Tournament winner identified; promotion gate honored; α gate blocks promotion when judges disagree. |
| `scenario_research.sh` | Full pipeline + adversary verdicts attached + survival arithmetic + synthesis filters by survival_score. |
| `scenario_resume.sh` | Failed phase reset to pending; retry succeeds; final status = completed; result file from retry visible. |
| `scenario_setup.sh` | `setup` creates correct symlinks (idempotent across re-runs); `uninstall` removes them; repo intact after both. |
| `scenario_witness.sh` | Markdown-driven follow-ups; editing the template propagates to next-run wording without code changes. |
| `scenario_malformed_inputs.sh` | 7 invalid-input cases across all 4 helpers exit non-zero. |

## When to add a scenario

Add a new scenario whenever:

- A skill prompt declares a behavior not yet exercised by an existing scenario
- A helper learns a new flag or detect-kind
- A bug surfaces in real use — the regression test is a scenario, not a unit test

Keep scenarios self-contained (`mktemp -d`, trap-cleanup, no shared state).
