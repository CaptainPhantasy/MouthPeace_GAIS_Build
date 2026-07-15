#!/usr/bin/env python3
"""Claude Code PreToolUse pre-execution-deny adapter for Goal Guard.

Claude Code invokes this BEFORE a tool runs. The Sentinel judges the *pending*
tool call (its name + input) together with the run's reasoning/transcript for
drift, deception, and — most importantly here — intent-to-violate, and can stop
the call before it executes:

    L3  -> deny  (the tool call is blocked before it runs)
    L2  -> ask   (Claude prompts you to approve)
    L0/L1/on-track -> allow (proceed; logged only)

This is the pre-execution complement to the PostToolUse Sentinel: it gates the
*moment*, not the next step.

Cost control: only judges *mutating* tools by default (override GUARD_SENTINEL_TOOLS).
FAIL-OPEN: any error -> allow. The guard never wedges your run.

Wire it up in .claude/settings.json:

    {
      "hooks": {
        "PreToolUse": [
          { "hooks": [ { "type": "command",
              "command": "python3 /absolute/path/to/modules/goal-guard/adapters/claude_code/goalguard_pretooluse_hook.py" } ] }
        ]
      }
    }
"""

from __future__ import annotations

import json
import os
import sys


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def _allow() -> None:
    _emit({"continue": True})


def _pre_decision(decision: str, reason: str) -> None:
    # Modern schema + legacy keys for cross-version compatibility.
    _emit({
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": decision,           # "deny" | "ask"
            "permissionDecisionReason": reason,
        },
        "decision": "block" if decision == "deny" else "ask",
        "reason": reason,
    })


def _summarize_pending(payload: dict) -> str:
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input")
    parts = [f"ABOUT TO RUN (not yet executed) tool: {tool}"]
    if tool_input is not None:
        parts.append("proposed input: " + json.dumps(tool_input, default=str)[:1800])
    return "\n".join(parts)


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    project = payload.get("cwd") or os.getcwd()
    transcript = payload.get("transcript_path")
    tool_name = payload.get("tool_name")

    try:
        from goalguard import guard, sentinel
    except Exception:
        _allow()  # fail-open: guard unavailable
        return 0

    if not sentinel.should_check(tool_name):
        _allow()  # throttle: read-only tool, no judge call
        return 0

    try:
        result = guard.sentinel_checkpoint(
            project,
            transcript=transcript,
            recent_action=_summarize_pending(payload),
        )
    except Exception:
        _allow()  # fail-open: judge/model error
        return 0

    decision = sentinel.permission_for(result.get("action", "ok"))
    correction = result.get("correction") or ""
    problem = result.get("problem", "none")

    if decision == "allow" or not correction:
        _allow()
        return 0

    tag = {"deception": "untruthful output", "intent_violation": "policy bypass",
           "drift": "goal drift"}.get(problem, "issue")
    _pre_decision(decision, f"[Goal Guard — {tag}] {correction}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
