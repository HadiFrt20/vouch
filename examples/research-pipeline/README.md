# Research pipeline

A 3-stage pipeline demonstrating the full surface: stages, adversary
verification on Claim objects, budget gating.

## Run it (interactive)

In Claude Code, from this directory:

```
/vouch-init .          # accept the existing pipeline.md when prompted
/vouch-run .
/vouch-status .
```

## Run it (driver, no Claude)

The scenario script in `tests/scenarios/scenario_research.sh` simulates what
the skills + subagents would do, by using the helpers directly to mark
phases, attach claim verdicts, and finalise the run. Useful for verifying
the protocol end-to-end.

```bash
bash tests/scenarios/scenario_research.sh
```

## Expected outcome

- 3 phases complete
- 3 claims extracted; 2 confirmed against the corpus, 1 weakened
- Survival rate ~ 1.0; trust score ~ 0.6
- Budget: 4 spent of 5
