#!/usr/bin/env python3
"""vouch_state — atomic state file operations for vouch pipelines.

Skills shell out to this for race-free reads and writes against the
``.vouch/runs/{run_id}/state.json`` file. Uses fcntl flock + tmp+rename.

Usage::

    vouch_state.py init   <run_dir> --pipeline <pipeline.md>
    vouch_state.py read   <run_dir>
    vouch_state.py update <run_dir> --phase <name> --status <status> [--result-file F] [--error MSG]
    vouch_state.py finish <run_dir> --status <status> [--error MSG]
    vouch_state.py progress <run_dir>

Exit codes: 0 ok, 1 missing/invalid args, 2 file conflict / lock failure.
"""
from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import fcntl
import json
import os
import sys
import uuid
from pathlib import Path

VALID_STATUSES = {"pending", "running", "completed", "failed", "skipped"}
VALID_TERMINAL = {"completed", "failed"}


def _now() -> str:
    return dt.datetime.now(dt.timezone.utc).isoformat()


def _short_id() -> str:
    return uuid.uuid4().hex[:12]


@contextlib.contextmanager
def _locked(path: Path):
    """Cross-process advisory lock on a sibling .lock file."""
    lock_path = path.with_suffix(path.suffix + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _write_atomic(path: Path, payload: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(payload, indent=2, default=str))
    tmp.replace(path)


def _read(state_path: Path) -> dict:
    if not state_path.exists():
        sys.exit(f"state file not found: {state_path}")
    return json.loads(state_path.read_text())


def _progress_pct(state: dict) -> float:
    phases = state.get("phases", {})
    if not phases:
        return 0.0
    total = sum(p.get("weight", 1) for p in phases.values())
    if total == 0:
        return 0.0
    completed = sum(p["weight"] for p in phases.values() if p["status"] == "completed")
    running = sum(p["weight"] * 0.5 for p in phases.values() if p["status"] == "running")
    return round((completed + running) / total * 100, 2)


def cmd_init(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state_path = run_dir / "state.json"
    if state_path.exists() and not args.force:
        sys.exit(f"state already exists at {state_path} (use --force to overwrite)")

    if args.pipeline:
        phases = _parse_pipeline(Path(args.pipeline))
    elif args.phase:
        phases = {
            name: {"name": name, "weight": int(weight), "status": "pending",
                   "result": None, "error": None, "started_at": None, "completed_at": None}
            for name, weight in (p.split(":") for p in args.phase)
        }
    else:
        sys.exit("provide --pipeline or one or more --phase name:weight")

    state = {
        "id": args.id or _short_id(),
        "status": "pending",
        "phases": phases,
        "started_at": None,
        "completed_at": None,
        "error": None,
        "metadata": json.loads(args.metadata) if args.metadata else {},
    }
    with _locked(state_path):
        _write_atomic(state_path, state)
    print(json.dumps({"id": state["id"], "run_dir": str(run_dir),
                      "phases": list(phases.keys())}, indent=2))
    return 0


def _parse_pipeline(path: Path) -> dict:
    """Parse a pipeline.md file containing a YAML-style block of stages.

    Recognised format (kept simple — no PyYAML dependency)::

        ## Stages

        - name: fetch
          weight: 20
        - name: transform
          weight: 80
    """
    if not path.exists():
        sys.exit(f"pipeline file not found: {path}")
    text = path.read_text()
    phases = {}
    current = None
    for raw in text.splitlines():
        line = raw.strip()
        if line.startswith("- name:"):
            if current:
                phases[current["name"]] = current
            current = {
                "name": line.split(":", 1)[1].strip(),
                "weight": 1,
                "status": "pending",
                "result": None,
                "error": None,
                "started_at": None,
                "completed_at": None,
            }
        elif line.startswith("weight:") and current:
            try:
                current["weight"] = int(line.split(":", 1)[1].strip())
            except ValueError:
                pass
    if current:
        phases[current["name"]] = current
    if not phases:
        sys.exit(f"no stages found in {path} (expected '- name: NAME' / 'weight: N' lines)")
    return phases


def cmd_read(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state_path = run_dir / "state.json"
    with _locked(state_path):
        state = _read(state_path)
    state["progress_pct"] = _progress_pct(state)
    print(json.dumps(state, indent=2, default=str))
    return 0


def cmd_progress(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state_path = run_dir / "state.json"
    with _locked(state_path):
        state = _read(state_path)
    out = {
        "id": state["id"],
        "status": state["status"],
        "progress_pct": _progress_pct(state),
        "phases": {
            n: {"status": p["status"], "weight": p["weight"]}
            for n, p in state["phases"].items()
        },
    }
    print(json.dumps(out, indent=2))
    return 0


def cmd_update(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state_path = run_dir / "state.json"
    if args.status not in VALID_STATUSES:
        sys.exit(f"invalid status {args.status!r}; allowed: {sorted(VALID_STATUSES)}")

    with _locked(state_path):
        state = _read(state_path)
        if args.phase not in state["phases"]:
            sys.exit(f"unknown phase {args.phase!r}; defined: {list(state['phases'])}")
        phase = state["phases"][args.phase]

        # First-touch: stamp run-level started_at
        if state["status"] == "pending" and args.status == "running":
            state["status"] = "running"
            state["started_at"] = state["started_at"] or _now()

        phase["status"] = args.status
        if args.status == "running" and not phase["started_at"]:
            phase["started_at"] = _now()
        if args.status in {"completed", "failed", "skipped"}:
            phase["completed_at"] = _now()
        if args.error:
            phase["error"] = args.error
        if args.result_file:
            rp = Path(args.result_file)
            if not rp.exists():
                sys.exit(f"result file not found: {rp}")
            try:
                phase["result"] = json.loads(rp.read_text())
            except json.JSONDecodeError:
                phase["result"] = rp.read_text()

        _write_atomic(state_path, state)

    state["progress_pct"] = _progress_pct(state)
    print(json.dumps({"phase": args.phase, "status": args.status,
                      "progress_pct": state["progress_pct"]}, indent=2))
    return 0


def cmd_finish(args: argparse.Namespace) -> int:
    run_dir = Path(args.run_dir).resolve()
    state_path = run_dir / "state.json"
    if args.status not in VALID_TERMINAL:
        sys.exit(f"finish status must be one of {sorted(VALID_TERMINAL)}")

    with _locked(state_path):
        state = _read(state_path)
        state["status"] = args.status
        state["completed_at"] = _now()
        if args.error:
            state["error"] = args.error
        _write_atomic(state_path, state)

    print(json.dumps({"id": state["id"], "status": state["status"],
                      "progress_pct": _progress_pct(state)}, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vouch_state",
                                description="Atomic state for vouch pipelines.")
    sub = p.add_subparsers(dest="cmd", required=True)

    init = sub.add_parser("init")
    init.add_argument("run_dir")
    init.add_argument("--pipeline", help="pipeline.md describing stages")
    init.add_argument("--phase", action="append",
                      help="alternative to --pipeline: name:weight (repeatable)")
    init.add_argument("--id", help="explicit run id (default: random 12-char hex)")
    init.add_argument("--metadata", help="JSON metadata to attach")
    init.add_argument("--force", action="store_true")
    init.set_defaults(func=cmd_init)

    rd = sub.add_parser("read")
    rd.add_argument("run_dir")
    rd.set_defaults(func=cmd_read)

    pg = sub.add_parser("progress")
    pg.add_argument("run_dir")
    pg.set_defaults(func=cmd_progress)

    up = sub.add_parser("update")
    up.add_argument("run_dir")
    up.add_argument("--phase", required=True)
    up.add_argument("--status", required=True)
    up.add_argument("--result-file")
    up.add_argument("--error")
    up.set_defaults(func=cmd_update)

    fin = sub.add_parser("finish")
    fin.add_argument("run_dir")
    fin.add_argument("--status", required=True)
    fin.add_argument("--error")
    fin.set_defaults(func=cmd_finish)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
