# Research pipeline

Fetches passages from a small corpus, extracts factual claims, then synthesises
a summary. Adversary verification runs on the extracted claims; only surviving
claims feed the synthesiser.

## Stages

- name: fetch
  weight: 10
  description: load passages from the corpus that match the topic

- name: extract
  weight: 50
  description: identify factual claims across the fetched passages

- name: synthesize
  weight: 40
  description: combine surviving claims into a paragraph summary

## Verification

modes: [source_verification, cross_reference]

## Budget

initial: 5
cost_per_stage:
  fetch: 0
  extract: 2
  synthesize: 2
