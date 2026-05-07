# Skill-vs-skill tournament

Three candidate `SKILL.md` files for a hypothetical `/summarize` skill. The
tournament decides which deserves the `@production` alias.

This shows that `/vouch-promote` is **not just for prompts**. Candidates here
are skill-instruction files. The same protocol applies to subagent
definitions (`agents/*.md`), `settings.json` permission sets, MCP server
configs, hook configurations, or whole `pipeline.md` files.

## Run it

```bash
python3 ../../helpers/vouch_tournament.py run tournament.json
```

## Expected outcome

```
winner   : v_chain
margin   : ~34
alpha    : -0.26   ← negative; judges genuinely disagree
promoted : False   ← α gate refuses promotion
```

`v_chain` does have the highest ELO, but the **α gate refuses to promote**
because judges measure orthogonal things: `completion-quality` votes "more
thorough wins" while `latency-fit` votes "faster wins" on every pair. The
gate is doing its job — *don't ship when your judges literally disagree.*

To force a promotion you'd need to either:

1. Drop `latency-fit` from the round (decide thoroughness matters more)
2. Add a meta-judge that weights both axes into one verdict
3. Lower `alpha_threshold` (acknowledge you accept noisier judging)

Each is a *deliberate* decision instead of an accidental ship. That's the
point of the gate.

## What this looks like in practice

## What this looks like in practice — usage

You wrote a new version of one of your skills. You believe it's better. Don't
ship on belief:

```
/vouch-promote skill-tournament.md
```

The tournament runs your judges against both versions, ELO + α decide, and
the alias only flips if the evidence holds up. If the judges disagree (low
α), the new version stays in `@candidate` and you investigate before shipping.

## Tournament-able artifacts

| Artifact | Judge axes |
|---|---|
| Two `SKILL.md` files | structure / completion-quality / cross-vendor / latency |
| Two `agents/*.md` subagents | reliability / scope-creep / failure-mode coverage |
| Two `settings.json` permission sets | security catches / friction / dev-loop speed |
| Two MCP configs | tool selection accuracy / latency / cost |
| Two hook configurations | bugs caught / false-positive rate / overhead |
| Two `pipeline.md` Loop shapes | end-to-end quality / cost / failure recovery |

The tournament doesn't know what kind of artifact it's judging. It just runs
the judges you give it. Ship a more general judge in your `agents/` directory
and the same flow works for any of these.
