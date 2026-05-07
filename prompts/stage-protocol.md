# Stage protocol

What a stage in `pipeline.md` looks like, and what it produces.

## Pipeline.md shape

```markdown
# {pipeline name}

{description}

## Stages

- name: fetch
  weight: 20
  description: pull the input data from the upstream source

- name: extract
  weight: 30
  description: surface the relevant claims from the fetched data

- name: synthesize
  weight: 50
  description: combine surviving claims into the final summary

## Verification

modes: [source_verification, cross_reference]

## Budget

initial: 100
cost_per_stage:
  fetch: 0
  extract: 30
  synthesize: 50
```

The `## Verification` and `## Budget` sections are optional. When absent, no
adversary runs and stages have no cost gate.

## Stage result shapes

A stage writes a single JSON value to `$RUN_DIR/$PHASE.result.json`. Three
recognised shapes:

### 1. Plain result

Anything serialisable. The Loop just stores it on the phase.

```json
{"summary": "produced X bullets", "n_records": 42}
```

### 2. Result with claims

If the result is an object containing a `claims` array, the adversary picks
those claims up (provided `## Verification` is configured).

```json
{
  "summary": "...",
  "claims": [
    {"text": "claim 1", "confidence": 0.85, "source_url": "https://..."},
    {"text": "claim 2", "confidence": 0.7}
  ]
}
```

### 3. Bare claims list

A top-level array whose items are claim objects also triggers adversary
verification.

```json
[
  {"text": "claim 1", "confidence": 0.85},
  {"text": "claim 2", "confidence": 0.4}
]
```

## Phase status semantics

| status | meaning |
|---|---|
| `pending`   | not yet started |
| `running`   | currently executing (mid-stage subagent run) |
| `completed` | result file written, no error |
| `failed`    | subagent returned an error envelope |
| `skipped`   | budget exhausted OR `skip_if` evaluated true OR `on_error: skip` after a failure |

Run-level status follows the worst phase: any `failed` and `on_error: fail` →
run `failed`; otherwise once all phases are terminal → run `completed`.

## Progress %

```
progress_pct = sum(p.weight for p in completed) / sum(p.weight for all)
             + 0.5 × sum(p.weight for p in running) / sum(p.weight for all)
```

Running phases contribute half their weight, so the percentage moves smoothly
during execution.
