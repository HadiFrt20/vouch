#!/usr/bin/env bash
# Scenario 9 — setup script creates the right symlinks; uninstall removes them.
#
# Uses an isolated $HOME so we don't disturb the user's real ~/.claude.

set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$HERE/../.." && pwd)"

FAKE_HOME=$(mktemp -d -t vouch-setup-XXXXXX)
trap "rm -rf $FAKE_HOME" EXIT

# Run setup with HOME pointed at the sandbox
HOME="$FAKE_HOME" "$ROOT/setup" >/dev/null

# Verify all 7 skills + 3 agents are symlinks pointing into the repo
expected_skills=(vouch-init vouch-run vouch-verify vouch-promote vouch-witness vouch-status vouch-resume)
expected_agents=(vouch-stage vouch-adversary vouch-judge)

for s in "${expected_skills[@]}"; do
    p="$FAKE_HOME/.claude/skills/$s"
    if [[ ! -L "$p" ]]; then echo "FAIL: $p is not a symlink" >&2; exit 1; fi
    target=$(readlink "$p")
    if [[ "$target" != "$ROOT/skills/$s" ]]; then
        echo "FAIL: $s symlink points to $target (expected $ROOT/skills/$s)" >&2
        exit 1
    fi
    if [[ ! -f "$p/SKILL.md" ]]; then echo "FAIL: $p/SKILL.md missing" >&2; exit 1; fi
done

for a in "${expected_agents[@]}"; do
    p="$FAKE_HOME/.claude/agents/$a.md"
    if [[ ! -L "$p" ]]; then echo "FAIL: $p is not a symlink" >&2; exit 1; fi
    target=$(readlink "$p")
    if [[ "$target" != "$ROOT/agents/$a.md" ]]; then
        echo "FAIL: $a symlink target wrong: $target" >&2
        exit 1
    fi
done

# Re-run setup — should be idempotent (replaces existing symlinks)
HOME="$FAKE_HOME" "$ROOT/setup" >/dev/null

# Now uninstall — should remove all symlinks but leave the repo alone
HOME="$FAKE_HOME" "$ROOT/uninstall" >/dev/null

for s in "${expected_skills[@]}"; do
    p="$FAKE_HOME/.claude/skills/$s"
    if [[ -L "$p" || -e "$p" ]]; then echo "FAIL: $p still exists after uninstall" >&2; exit 1; fi
done
for a in "${expected_agents[@]}"; do
    p="$FAKE_HOME/.claude/agents/$a.md"
    if [[ -L "$p" || -e "$p" ]]; then echo "FAIL: $p still exists after uninstall" >&2; exit 1; fi
done

# Repo should still be intact
if [[ ! -f "$ROOT/skills/vouch-run/SKILL.md" ]]; then
    echo "FAIL: uninstall damaged the repo" >&2
    exit 1
fi

echo "OK: scenario_setup — install (×2 idempotent), all symlinks correct, uninstall clean"
