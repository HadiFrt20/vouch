<div align="center">

# vouch

### Pre-flight checks for AI agents.

**Stage. Verify. Promote.**
Every claim earns its quote. Every prompt earns its place. Every dollar gets debited atomically.

[![License](https://img.shields.io/badge/license-Apache%202.0-black.svg?style=flat-square)](LICENSE)
[![Python](https://img.shields.io/badge/python-3.10%2B-black.svg?style=flat-square)](https://www.python.org)
[![Status](https://img.shields.io/badge/status-alpha-orange.svg?style=flat-square)]()
[![Tests](https://img.shields.io/badge/scenarios-10%2F10-brightgreen.svg?style=flat-square)]()
[![Deps](https://img.shields.io/badge/runtime%20deps-0-brightgreen.svg?style=flat-square)]()

**A Claude Code plugin.** 7 slash commands · 3 subagents · 4 stdlib helpers · ~2,400 LOC.

</div>

---

## ⚠️ The problem

Your agent shipped a recommendation last quarter. Six weeks later someone asks **"where did this number come from?"** Nobody knows.

Your team promoted prompt v3 because *it looked better.* It quietly regressed. Now nobody is sure which version is in production, or why.

Your scheduled agent rate-limited mid-run, crashed, left customer state half-mutated. The retry can't tell what was already done.

**You've reinvented the audit trail. Three times. Badly.**

## ✨ The fix

```bash
/vouch-init    .          # scaffold a pipeline
/vouch-run     .          # stages run; claims get verdicts; budget debits atomically
/vouch-promote spec.md    # tournament + α-gate before any prompt becomes @production
/vouch-witness checklist.md checks.json target.json   # markdown-driven follow-up questions
```

Every artifact ships with a **witness**: provenance, an adversary verdict, a budget receipt, a tournament ELO. Not as logs. As primitives.

## 🚀 Install in 60 seconds

```bash
git clone https://github.com/HadiFrt20/vouch ~/.vouch
cd ~/.vouch && ./setup
bash tests/scenarios/run_all.sh    # 10/10 should pass in ~10s
```

That's it. `setup` symlinks 7 skills into `~/.claude/skills/` and 3 subagents into `~/.claude/agents/`. Helpers stay in the repo. Uninstall: `./uninstall`.

## 🧱 What's in the box

<table>
<tr>
<td width="50%" valign="top">

### Slash commands

| | |
|---|---|
| `/vouch-init` | Scaffold a new pipeline. Interview, write `pipeline.md`, seed state. |
| `/vouch-run` | Execute the next pending stage. Re-runnable. Spawns `vouch-stage` subagents. |
| `/vouch-verify` | Run the 4-mode adversary; attach verdicts; compute survival rate. |
| `/vouch-promote` | Tournament-gate **any change** — prompts, skills, subagents, configs, hooks, whole pipelines. Promotion requires margin **and** Krippendorff α. |
| `/vouch-witness` | Markdown checklist; severity-weighted score; follow-up questions. |
| `/vouch-status` | Read-only dashboard. |
| `/vouch-resume` | Pick up a failed run from where it stopped. |

</td>
<td width="50%" valign="top">

### Subagents (Claude spawns these)

| | |
|---|---|
| `vouch-stage` | Executes one pipeline stage. Writes a result file. |
| `vouch-adversary` | Verifies a list of claims under any subset of 4 modes. |
| `vouch-judge` | Compares two candidates under one named criterion. |

### Python helpers (stdlib only)

| | |
|---|---|
| `vouch_state.py` | Atomic state ops. `flock` + tmp+rename. |
| `vouch_budget.py` | Race-free conditional debit. |
| `vouch_tournament.py` | ELO + progressive K + Krippendorff α. |
| `vouch_witness.py` | Parse markdown checklists; emit gap reports. |

</td>
</tr>
</table>

## 🎯 Three things you couldn't do before

### 1. Refuse to refute without a quote

```python
# adversary returns: { verdict: "refuted", quote: null }
# vouch downgrades to: { verdict: "unverifiable", evidence: "[downgraded: no source quote]" }
```

The verifier can't reach beyond what it can cite. *That single rule kills a class of bugs.*

### 2. Promote anything on evidence, not vibes

Tournaments work for **any** Claude Code artifact you'd otherwise A/B by feel:

| Comparing | Use it when |
|---|---|
| Two prompts | "v4 looks better than v3" — measure it |
| Two `SKILL.md` files | Skill rewrite — does it actually behave better? |
| Two subagent definitions | Alternative `agents/*.md` — which is more reliable? |
| Two `settings.json` / MCP configs | Permission/hook trade-offs — which catches more bugs? |
| Two whole `pipeline.md` files | Re-shape your Loop — which produces better outputs? |

```text
# tournament runs cheap → llm → cross-vendor judges with K=32 → 24 → 16
# promotion requires:
#     margin >= 50                  # the winner is meaningfully ahead
#     krippendorff_alpha >= 0.667   # judges actually agree
```

If v3 only "won" because one judge liked it, the α gate blocks promotion.
**No more change drift by feel — for any artifact you ship.**

### 3. Fail soft, never half-mutated

```python
budget = Budget(initial=100, cost_per_stage={"cheap": 1, "expensive": 50})
# When the wallet runs dry mid-pipeline:
#   stage marked SKIPPED with reason="budget exhausted"
#   run finalises FAILED with full state on disk
#   /vouch-resume picks up cleanly
```

Atomic debit invariant verified by a stress test: **400 parallel debits against a 200-balance wallet → exactly 200 succeed, balance → 0.**

## 📐 How it composes

```
┌──────────────────┐     ┌──────────────────┐
│  /vouch-run      │     │  /vouch-promote  │
└────────┬─────────┘     └────────┬─────────┘
         │ spawns                  │ spawns
         ▼                         ▼
┌──────────────────┐     ┌──────────────────┐
│  vouch-stage     │     │  vouch-judge     │
│  (subagent)      │     │  (subagent)      │
└────────┬─────────┘     └────────┬─────────┘
         │ writes result            │ writes verdict
         ▼                         ▼
   $RUN_DIR/$P.result.json    $TMP/match-N.json
         │                         │
         │ optional adversary       │
         ▼                         ▼
┌──────────────────┐     ┌──────────────────┐
│ vouch-adversary  │     │ vouch_tournament │
│  (subagent)      │     │  ELO + α gate    │
└────────┬─────────┘     └────────┬─────────┘
         ▼                         ▼
   verdicts (with quotes)    promoted? → registry alias mv

       throughout: vouch_state.py and vouch_budget.py own
       the atomic JSON files (flock + tmp+rename)
```

## 🧪 Tested in 10 scenarios

```
✓ basic_loop          state transitions, progress %, terminal status
✓ budget_exhaustion   stage skipped on insufficient balance
✓ concurrent_debit    400 parallel debits → exactly 200 succeed
✓ malformed_inputs    7 invalid-input cases all rejected
✓ pipeline_md_parse   markdown → ordered phases with weights
✓ promotion           winner correct + α gate blocks contested promotion
✓ research            adversary verdicts + survival filtering on synthesis
✓ resume              failed phase → reset → retry → completed
✓ setup               install symlinks idempotently; uninstall clean
✓ witness             markdown follow-ups; edits propagate to next run

passed: 10   failed: 0   elapsed: 8s
```

## 📦 Four example pipelines

```bash
# A research pipeline with corpus-grounded adversary
cat examples/research-pipeline/pipeline.md
bash tests/scenarios/scenario_research.sh

# A prompt-vs-prompt tournament with mock judges
python3 helpers/vouch_tournament.py run examples/prompt-promotion/tournament.json

# A SKILL.md-vs-SKILL.md tournament — same protocol, different artifact
python3 helpers/vouch_tournament.py run examples/skill-tournament/tournament.json

# A markdown-driven intake checklist (edit the .md, follow-ups update)
python3 helpers/vouch_witness.py evaluate \
    examples/intake-checklist/checklist.md \
    examples/intake-checklist/checks.json \
    examples/intake-checklist/sample-weak.json
```

The skill-tournament example shows the α gate doing real work: when judges
measure orthogonal things (`completion-quality` vs `latency-fit`), it
**refuses to promote** even though one candidate has the highest ELO.
That's not a bug — that's the discipline.

## 🧠 The discipline

> Every artifact your agent emits should arrive with a witness.
> Not as documentation. Not as a logging line. As a primitive.

vouch makes the witness primitive. The Loop runs your stages; the Adversary attaches verdicts to anything you mark as a Claim; the Budget deducts atomically; the Tournament blocks promotions when judges disagree. **Compose them in whatever shape your problem needs.**

## 🆚 Comparable to

| | Provenance | Adversary | Atomic budget | Tournament promotion | Markdown-driven |
|---|:-:|:-:|:-:|:-:|:-:|
| LangChain callbacks | Logs | ✗ | ✗ | ✗ | ✗ |
| LangSmith | ✓ | ✗ | ✗ | ✗ | ✗ |
| MLflow Tracing | ✓ | ✗ | ✗ | ✗ | ✗ |
| DSPy optimizers | ✗ | ✗ | ✗ | Implicit | ✗ |
| **vouch** | **✓** | **✓** | **✓** | **✓** | **✓** |

Different layer. Use vouch *with* whichever runtime you already have — it's a discipline, not a runtime.

## 🛣 Status & roadmap

**Alpha.** APIs in flux. Tested via 10 scenario drivers; skill prompts may iterate.

Next:
- [ ] MLflow registry adapter (`/vouch-promote` writes to MLflow Prompt Registry instead of local files)
- [ ] Telemetry: emit OpenTelemetry spans per stage
- [ ] Worked example: continuously-improving research agent (`/vouch-run` + `/vouch-promote` in one cron)
- [ ] Marketplace listing for the Claude Code plugin registry

## 🤝 Contributing

Issues and PRs welcome. **Keep helpers stdlib-only** — if a piece of work needs a heavier dep, build it as a separate skill that doesn't ship with the core.

If you ship vouch in production, please [open an issue](https://github.com/HadiFrt20/vouch/issues) so we know — pre-1.0 we want to hear about every real use.

## 📜 License

[Apache 2.0](LICENSE).

---

<div align="center">

**If vouch saved you a debug session, [star the repo](https://github.com/HadiFrt20/vouch).**

*Built with [Claude Code](https://claude.com/claude-code).*

</div>
