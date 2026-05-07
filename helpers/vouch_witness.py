#!/usr/bin/env python3
"""vouch_witness — markdown-driven checklist runner.

Parses a markdown template (H2 sections, pipe-tables of fields), runs the
``checks.json`` rule file against a target document, and emits a witness
report with severity-weighted score and per-gap follow-up questions sourced
from the template (not from code).

Templates:

    ## Section Name

    | Question | Expected |
    |---|---|
    | What problem are we solving? | one paragraph |
    | Who feels the pain today? | role / team |

Checks file (JSON) — each entry links a runtime detector to a template field::

    [
      {
        "id": "problem",
        "label": "Problem stated",
        "severity": "critical",
        "section": "Section Name",
        "template_field_idx": 0,
        "detect": {"kind": "field_present", "field": "problem", "min_length": 20}
      },
      {
        "id": "pain_owner",
        "severity": "high",
        "section": "Section Name",
        "template_field_idx": 1,
        "detect": {"kind": "regex", "pattern": "VP|director|head", "in_field": "owner"}
      }
    ]

Detect kinds shipped:

    field_present     — bool(target.get(field)), optional min_length
    field_equals      — target.get(field) == value
    regex             — re.search(pattern, target.get(field, ""))
    contains_keyword  — case-insensitive substring (pipe-separated alternates)
    custom            — pluggable: target[detect["check"]] is truthy

Usage::

    vouch_witness.py parse <template.md> [--out template.json]
    vouch_witness.py evaluate <template.md> <checks.json> <target.json> [--out report.json]

Severity weights: critical=3, high=2, medium=1, low=0.5.
Score thresholds: good >=0.8, acceptable >=0.5, else poor.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path
from typing import Any

SEVERITY_WEIGHTS = {"critical": 3.0, "high": 2.0, "medium": 1.0, "low": 0.5}
THRESH_GOOD = 0.8
THRESH_ACCEPT = 0.5


def parse_template(path: Path) -> dict[str, list[dict]]:
    text = path.read_text(encoding="utf-8")
    sections: dict[str, list[dict]] = {}
    current = None
    idx = 0
    headers_seen = False
    for raw in text.splitlines():
        m = re.match(r"^##\s+(.+)", raw)
        if m:
            current = m.group(1).strip()
            sections[current] = []
            idx = 0
            headers_seen = False
            continue
        if current is None:
            continue
        line = raw.strip()
        if line.startswith("|") and line.endswith("|"):
            cells = [c.strip() for c in line.strip("|").split("|")]
            if all(re.match(r"^-+$", c) for c in cells):
                continue
            if not headers_seen:
                headers_seen = True
                continue
            if len(cells) < 2:
                continue
            question = cells[0]
            expected = " | ".join(c for c in cells[1:] if c)
            sections[current].append({
                "section": current,
                "index": idx,
                "question": question,
                "expected": expected,
            })
            idx += 1
    return sections


def hint_for(field: dict) -> str:
    if field["expected"] and field["expected"] not in ("", "|"):
        return f"{field['question']} (e.g., {field['expected']})"
    return field["question"]


def followup(check: dict, template: dict[str, list[dict]]) -> str:
    section = check.get("section")
    idx = check.get("template_field_idx")
    if section is None or idx is None:
        return f"{check.get('label', check.get('id', 'check'))}?"
    fields = template.get(section, [])
    if 0 <= idx < len(fields):
        return hint_for(fields[idx])
    return f"{check.get('label', check.get('id', 'check'))}?"


def _detect(check: dict, target: dict) -> bool:
    d = check.get("detect", {})
    kind = d.get("kind", "field_present")
    if kind == "field_present":
        v = target.get(d["field"])
        if v is None:
            return False
        if isinstance(v, str):
            return len(v.strip()) >= int(d.get("min_length", 1))
        return bool(v)
    if kind == "field_equals":
        return target.get(d["field"]) == d.get("value")
    if kind == "regex":
        v = str(target.get(d.get("in_field", ""), ""))
        return bool(re.search(d["pattern"], v, re.IGNORECASE))
    if kind == "contains_keyword":
        v = str(target.get(d.get("in_field", ""), "")).lower()
        terms = [t.strip().lower() for t in d.get("any_of", "").split("|") if t.strip()]
        return any(t in v for t in terms)
    if kind == "custom":
        return bool(target.get(d.get("check"), False))
    sys.exit(f"unknown detect.kind: {kind}")


def evaluate(target: dict, checks: list[dict], template: dict[str, list[dict]]) -> dict:
    total_w = 0.0
    earned_w = 0.0
    gaps = []
    passed = []
    for c in checks:
        weight = SEVERITY_WEIGHTS.get(c.get("severity", "medium"), 1.0)
        total_w += weight
        try:
            ok = _detect(c, target)
        except Exception:
            ok = False
        if ok:
            earned_w += weight
            passed.append(c["id"])
        else:
            gaps.append({
                "id": c["id"],
                "label": c.get("label", c["id"]),
                "severity": c.get("severity", "medium"),
                "section": c.get("section"),
                "followup_question": followup(c, template),
            })
    score = (earned_w / total_w) if total_w > 0 else 0.0
    label = "good" if score >= THRESH_GOOD else "acceptable" if score >= THRESH_ACCEPT else "poor"
    return {
        "overall_score": round(score, 4),
        "label": label,
        "gaps": gaps,
        "passed": passed,
        "total_checks": len(checks),
    }


def cmd_parse(args: argparse.Namespace) -> int:
    template = parse_template(Path(args.template))
    out = json.dumps(template, indent=2)
    if args.out:
        Path(args.out).write_text(out)
    print(out)
    return 0


def cmd_evaluate(args: argparse.Namespace) -> int:
    template = parse_template(Path(args.template))
    checks = json.loads(Path(args.checks).read_text())
    target = json.loads(Path(args.target).read_text())
    if not isinstance(checks, list):
        sys.exit("checks.json must be a JSON array")
    if not isinstance(target, dict):
        sys.exit("target.json must be a JSON object")
    report = evaluate(target, checks, template)
    out = json.dumps(report, indent=2)
    if args.out:
        Path(args.out).write_text(out)
    print(out)
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vouch_witness")
    sub = p.add_subparsers(dest="cmd", required=True)

    par = sub.add_parser("parse")
    par.add_argument("template")
    par.add_argument("--out")
    par.set_defaults(func=cmd_parse)

    ev = sub.add_parser("evaluate")
    ev.add_argument("template")
    ev.add_argument("checks")
    ev.add_argument("target")
    ev.add_argument("--out")
    ev.set_defaults(func=cmd_evaluate)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
