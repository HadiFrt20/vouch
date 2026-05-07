---
name: vouch-verify
description: Run the vouch adversary against a list of Claims and write verified verdicts. Use this standalone (without /vouch-run) when you already have a JSON file of claims and want survival scores attached. Invokes the vouch-adversary subagent under the hood.
---

You are the verification skill. Take a claims file in, write a verified-claims file out.

## Arguments

`/vouch-verify <claims_file> [--modes M1,M2,...] [--out OUT]`

- `claims_file` — JSON. Either an array of claim objects, or a JSON object with a `claims` array.
- `--modes` — comma-separated subset of `source_verification`, `contradiction_search`, `cross_reference`, `temporal_check`. Default: all four.
- `--out` — output path. Default: `<claims_file>.verified.json`.

## Step 1 — Validate the input

A claim object must have at least:

```json
{
  "text": "string — the claim itself",
  "confidence": 0.0
}
```

Optional fields the verifier can read or set: `source_url`, `quote`, `verdict`, `confidence_delta`, `adversary_evidence`, `verification_mode`. The verdict enum is `confirmed | refuted | weakened | unverifiable | pending`.

If any item is missing `text` or `confidence`, refuse and list the offending indices.

## Step 2 — Spawn the adversary

Use the Agent tool with `subagent_type: "vouch-adversary"`. Pass it:

- the claims file path (read-only access)
- the list of modes
- the path to write the verified file

The adversary returns when done; the file at `--out` exists.

## Step 3 — Compute survival metrics

Read the verified file. For each claim, compute `survival_score` per the rule:

| verdict        | survival_score                          |
|----------------|------------------------------------------|
| `confirmed`    | `confidence`                             |
| `weakened`     | `max(0, confidence + confidence_delta)`  |
| `refuted`      | `0.0`                                    |
| `unverifiable` | `confidence * 0.5`                       |
| `pending`      | `confidence` (provisional)               |

Then compute and report:

- `survival_rate = (confirmed + weakened) / (confirmed + weakened + refuted)`
  (None if denominator is 0; pending and unverifiable are EXCLUDED from the denominator.)
- `trust_score = mean(survival_score)`

## Step 4 — Print the summary

```
claims         : N
confirmed      : N
weakened       : N (Δ avg: ...)
refuted        : N
unverifiable   : N
pending        : N

survival_rate  : 0.xx (or n/a)
trust_score    : 0.xx

written to     : <OUT>
```

## Quote-on-refute rule (load-bearing)

The verifier MUST attach a direct quote (`quote` field) when setting verdict to `refuted` or `weakened`. If the subagent returns a refuted/weakened claim without a quote, this skill must downgrade that claim to `unverifiable` and append `"[downgraded: no source quote]"` to its `adversary_evidence`. This rule prevents the adversary from reaching beyond what it can cite.

## Rules

- Never modify the input file in place.
- Never invent quotes. If the subagent didn't provide one, downgrade — don't backfill.
- A claim with verdict `pending` after verification means the adversary explicitly couldn't decide; report it but don't penalise it.
- `--modes` order matters: the first mode that yields `confirmed` or `refuted` short-circuits the rest. Other modes can only weaken or mark unverifiable.
