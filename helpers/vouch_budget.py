#!/usr/bin/env python3
"""vouch_budget — atomic, race-free debit. Backs the Budget primitive in skills.

Stored as JSON at ``{wallet_path}`` with file-locking on each operation so
parallel skills (or subagents) cannot overdraw.

Usage::

    vouch_budget.py init   <wallet_path> --balance 100 [--cost-per-stage '{"a":3,"b":4}']
    vouch_budget.py debit  <wallet_path> --stage <name>
    vouch_budget.py credit <wallet_path> --amount <int>
    vouch_budget.py show   <wallet_path>

Exit codes::

    0   debit succeeded / op succeeded
    2   insufficient balance (no mutation; show JSON envelope)
    3   wallet missing / corrupt
"""
from __future__ import annotations

import argparse
import contextlib
import fcntl
import json
import os
import sys
from pathlib import Path


@contextlib.contextmanager
def _locked(path: Path):
    lock_path = path.with_suffix(path.suffix + ".lock")
    lock_path.parent.mkdir(parents=True, exist_ok=True)
    fd = os.open(lock_path, os.O_RDWR | os.O_CREAT, 0o600)
    try:
        fcntl.flock(fd, fcntl.LOCK_EX)
        yield
    finally:
        fcntl.flock(fd, fcntl.LOCK_UN)
        os.close(fd)


def _read(path: Path) -> dict:
    if not path.exists():
        sys.exit(3)
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        sys.exit(3)


def _write(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(path.suffix + ".tmp")
    tmp.write_text(json.dumps(data, indent=2))
    tmp.replace(path)


def _cost_for(wallet: dict, stage: str) -> int:
    cost_map = wallet.get("cost_per_stage")
    if isinstance(cost_map, dict):
        return int(cost_map.get(stage, 0))
    return int(cost_map or 0)


def cmd_init(args: argparse.Namespace) -> int:
    path = Path(args.wallet_path)
    if path.exists() and not args.force:
        sys.exit(f"wallet already exists: {path} (use --force to overwrite)")
    if args.balance < 0:
        sys.exit("balance must be non-negative")
    cost = json.loads(args.cost_per_stage) if args.cost_per_stage else 1
    wallet = {
        "balance": args.balance,
        "initial": args.balance,
        "spent": 0,
        "cost_per_stage": cost,
    }
    with _locked(path):
        _write(path, wallet)
    print(json.dumps(wallet, indent=2))
    return 0


def cmd_debit(args: argparse.Namespace) -> int:
    path = Path(args.wallet_path)
    with _locked(path):
        wallet = _read(path)
        cost = _cost_for(wallet, args.stage)
        if cost == 0:
            envelope = {"ok": True, "stage": args.stage, "cost": 0,
                        "balance": wallet["balance"], "reason": "no cost"}
            print(json.dumps(envelope, indent=2))
            return 0
        if wallet["balance"] >= cost:
            wallet["balance"] -= cost
            wallet["spent"] += cost
            _write(path, wallet)
            envelope = {"ok": True, "stage": args.stage, "cost": cost,
                        "balance": wallet["balance"], "spent": wallet["spent"]}
            print(json.dumps(envelope, indent=2))
            return 0
        envelope = {"ok": False, "stage": args.stage, "cost": cost,
                    "balance": wallet["balance"], "reason": "insufficient"}
        print(json.dumps(envelope, indent=2))
        return 2


def cmd_credit(args: argparse.Namespace) -> int:
    path = Path(args.wallet_path)
    if args.amount <= 0:
        sys.exit("credit amount must be positive")
    with _locked(path):
        wallet = _read(path)
        wallet["balance"] += args.amount
        _write(path, wallet)
    print(json.dumps({"ok": True, "amount": args.amount,
                      "balance": wallet["balance"]}, indent=2))
    return 0


def cmd_show(args: argparse.Namespace) -> int:
    path = Path(args.wallet_path)
    with _locked(path):
        wallet = _read(path)
    print(json.dumps(wallet, indent=2))
    return 0


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="vouch_budget",
                                description="Atomic budget for vouch pipelines.")
    sub = p.add_subparsers(dest="cmd", required=True)

    init = sub.add_parser("init")
    init.add_argument("wallet_path")
    init.add_argument("--balance", type=int, required=True)
    init.add_argument("--cost-per-stage", help="JSON dict {stage: cost} or single int")
    init.add_argument("--force", action="store_true")
    init.set_defaults(func=cmd_init)

    deb = sub.add_parser("debit")
    deb.add_argument("wallet_path")
    deb.add_argument("--stage", required=True)
    deb.set_defaults(func=cmd_debit)

    cre = sub.add_parser("credit")
    cre.add_argument("wallet_path")
    cre.add_argument("--amount", type=int, required=True)
    cre.set_defaults(func=cmd_credit)

    sh = sub.add_parser("show")
    sh.add_argument("wallet_path")
    sh.set_defaults(func=cmd_show)

    args = p.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    sys.exit(main())
