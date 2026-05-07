#!/usr/bin/env python3
"""vouch_tournament — ELO + progressive K + Krippendorff α gate.

The promotion gate. Skills feed in a verdict file describing matches; this
helper computes final ELO standings, the inter-judge agreement α, and a
boolean 'promoted' decision based on margin and α thresholds.

Verdict file format (JSON)::

    {
      "candidates": ["v1", "v2", "v3"],
      "starting_rating": 1200,
      "promotion_margin": 50,
      "alpha_threshold": 0.667,
      "rounds": [
        {
          "name": "cheap",
          "k": 32,
          "matches": [
            {"a": "v1", "b": "v2", "judge": "len",       "winner": "b"},
            {"a": "v1", "b": "v2", "judge": "structure", "winner": "b"},
            {"a": "v1", "b": "v3", "judge": "len",       "winner": "a"},
            ...
          ]
        },
        {"name": "llm",   "k": 24, "matches": [...]},
        {"name": "cross", "k": 16, "matches": [...]}
      ]
    }

Usage::

    vouch_tournament.py run <verdict_file> [--out RESULT_FILE]

Output (and written to RESULT_FILE if given)::

    {
      "standings": {"v2": 1284.7, "v1": 1183.5, "v3": 1131.8},
      "winner": "v2",
      "alpha": 1.0,
      "margin": 101.2,
      "promoted": true,
      "history": [...]
    }

Exit codes: 0 ok, 1 bad input.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Optional


def expected_score(rating_a: float, rating_b: float) -> float:
    return 1.0 / (1.0 + 10 ** ((rating_b - rating_a) / 400))


def elo_update(rating: float, expected: float, actual: float, k: float) -> float:
    return rating + k * (actual - expected)


def _winner_to_actual(winner: Optional[str], side: str) -> float:
    if winner is None or winner == "draw":
        return 0.5
    if side == "a":
        return 1.0 if winner == "a" else 0.0
    return 1.0 if winner == "b" else 0.0


def krippendorff_alpha(verdicts: list[list[Optional[str]]]) -> Optional[float]:
    """Nominal α with NaN-as-missing (None → ignored).

    Each ``verdicts[i]`` is the list of judges' verdicts on unit i. Units
    with <2 valid raters are dropped.
    """
    if not verdicts:
        return None
    valid_units = []
    for unit in verdicts:
        non_null = [v for v in unit if v is not None]
        if len(non_null) >= 2:
            valid_units.append(non_null)
    if not valid_units:
        return None

    do_num = 0
    do_den = 0
    all_categories: list = []
    for unit in valid_units:
        m = len(unit)
        all_categories.extend(unit)
        for i in range(m):
            for j in range(m):
                if i != j and unit[i] != unit[j]:
                    do_num += 1
        do_den += m * (m - 1)

    if do_den == 0:
        return 1.0

    n = len(all_categories)
    if n < 2:
        return None
    counts: dict = {}
    for c in all_categories:
        counts[c] = counts.get(c, 0) + 1

    de_num = 0
    cats = list(counts.keys())
    for i in range(len(cats)):
        for j in range(len(cats)):
            if i != j:
                de_num += counts[cats[i]] * counts[cats[j]]
    de_den = n * (n - 1)
    if de_den == 0:
        return 1.0
    do = do_num / do_den
    de = de_num / de_den
    if de == 0:
        return 1.0
    return 1.0 - (do / de)


def run_tournament(spec: dict) -> dict:
    candidates: list[str] = list(spec["candidates"])
    if len(candidates) < 2:
        sys.exit("tournament needs at least 2 candidates")

    starting = float(spec.get("starting_rating", 1200))
    promotion_margin = float(spec.get("promotion_margin", 50))
    alpha_threshold = spec.get("alpha_threshold")

    ratings = {c: starting for c in candidates}
    history: list[dict] = []

    # Group judges-per-pair-per-round to compute α
    per_match_verdicts: list[list[Optional[str]]] = []
    pair_judges_by_round: dict[tuple, list[Optional[str]]] = {}

    for round_ in spec["rounds"]:
        k = float(round_.get("k", 32))
        rname = round_.get("name", "round")
        for m in round_.get("matches", []):
            a, b, winner = m["a"], m["b"], m.get("winner")
            judge = m.get("judge", "judge")
            actual_a = _winner_to_actual(winner, "a")
            exp_a = expected_score(ratings[a], ratings[b])
            new_a = elo_update(ratings[a], exp_a, actual_a, k)
            new_b = elo_update(ratings[b], 1 - exp_a, 1 - actual_a, k)
            ratings[a], ratings[b] = new_a, new_b
            history.append({
                "round": rname, "k": k, "a": a, "b": b,
                "judge": judge, "winner": winner,
                "rationale": m.get("rationale", ""),
            })
            key = (rname, frozenset((a, b)))
            pair_judges_by_round.setdefault(key, []).append(winner)

    per_match_verdicts = list(pair_judges_by_round.values())
    alpha = krippendorff_alpha(per_match_verdicts) if per_match_verdicts else None

    sorted_pairs = sorted(ratings.items(), key=lambda kv: -kv[1])
    winner = sorted_pairs[0][0]
    margin = (
        sorted_pairs[0][1] - sorted_pairs[1][1] if len(sorted_pairs) >= 2 else 0.0
    )

    promoted = margin >= promotion_margin
    if alpha_threshold is not None and alpha is not None:
        promoted = promoted and alpha >= float(alpha_threshold)

    return {
        "standings": {c: round(r, 2) for c, r in sorted_pairs},
        "winner": winner,
        "alpha": round(alpha, 4) if alpha is not None else None,
        "margin": round(margin, 2),
        "promoted": promoted,
        "history": history,
    }


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vouch_tournament",
                                description="Run a vouch tournament.")
    sub = p.add_subparsers(dest="cmd", required=True)
    rn = sub.add_parser("run")
    rn.add_argument("verdict_file")
    rn.add_argument("--out", help="write result JSON to this path")
    args = p.parse_args(argv)

    spec_path = Path(args.verdict_file)
    if not spec_path.exists():
        sys.exit(f"verdict file not found: {spec_path}")
    try:
        spec = json.loads(spec_path.read_text())
    except json.JSONDecodeError as e:
        sys.exit(f"invalid JSON in {spec_path}: {e}")

    result = run_tournament(spec)
    out_text = json.dumps(result, indent=2)
    if args.out:
        Path(args.out).write_text(out_text)
    print(out_text)
    return 0


if __name__ == "__main__":
    sys.exit(main())
