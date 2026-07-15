"""Throttling for the mid-run Sentinel.

PostToolUse fires on every tool call, but judging every one is wasteful and slow.
By default the Sentinel only inspects *mutating* tools (writes, edits, shell), and
you can override with GUARD_SENTINEL_TOOLS (comma-separated allowlist). This keeps
cost and latency proportional to risk — read-only chatter is ignored.
"""

from __future__ import annotations

import os

# Tools that change state or run commands — worth a sentinel check.
DEFAULT_MUTATING = {
    "bash", "shell", "run", "exec", "execute",
    "write", "edit", "multiedit", "replace", "str_replace", "apply_patch",
    "notebookedit", "create", "delete", "remove", "move", "rename",
}


def _allowlist() -> set[str] | None:
    raw = os.getenv("GUARD_SENTINEL_TOOLS", "").strip()
    if not raw:
        return None
    return {t.strip().lower() for t in raw.split(",") if t.strip()}


def should_check(tool_name: str | None) -> bool:
    """Decide whether a tool call warrants a sentinel judge call."""
    name = (tool_name or "").strip().lower()
    if not name:
        return True  # unknown tool — err toward checking
    allow = _allowlist()
    if allow is not None:
        return any(a in name for a in allow)
    return any(m in name for m in DEFAULT_MUTATING)


def permission_for(action_kind: str) -> str:
    """Map a trust-ladder Action.kind to a PreToolUse permission decision.

    deny  -> block the pending tool call before it runs (L3 / escalate)
    ask   -> let Claude prompt the human to approve (L2)
    allow -> proceed; the check is only observed/suggested/on-track (L0/L1/ok)
    """
    if action_kind in ("correct", "escalate"):
        return "deny"
    if action_kind == "ask":
        return "ask"
    return "allow"
