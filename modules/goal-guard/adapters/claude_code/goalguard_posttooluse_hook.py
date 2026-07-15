#!/usr/bin/env python3
"""Claude Code PostToolUse Sentinel adapter for Goal Guard.

Claude Code invokes this right after each tool call. The Sentinel reads what just
happened (tool name + input + result) plus the run's reasoning/transcript, and
checks for three problems at once: goal DRIFT, DECEPTION (claims the evidence
doesn't support), and INTENT_VIOLATION (the agent deciding to do something it
shouldn't). At L3 it blocks and feeds a correction back so the run is steered
before the issue compounds. At L2 the result remains recorded as an operator
approval request; PostToolUse cannot turn that request into a human prompt, so
it must not automatically feed the correction back to Claude.

Cost control: by default it only judges *mutating* tools (writes/edits/shell);
read-only chatter is skipped. Override with GUARD_SENTINEL_TOOLS.

FAIL-OPEN: any error → let the run continue. The guard never wedges your work.

Wire it up in .claude/settings.json:

    {
      "hooks": {
        "PostToolUse": [
          { "hooks": [ { "type": "command",
              "command": "python3 /absolute/path/to/modules/goal-guard/adapters/claude_code/goalguard_posttooluse_hook.py" } ] }
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


def _summarize_action(payload: dict) -> str:
    tool = payload.get("tool_name", "")
    tool_input = payload.get("tool_input")
    tool_response = payload.get("tool_response")
    parts = [f"tool: {tool}"]
    if tool_input is not None:
        parts.append("input: " + json.dumps(tool_input, default=str)[:1500])
    if tool_response is not None:
        parts.append("result: " + json.dumps(tool_response, default=str)[:1500])
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
        _emit({"continue": True})  # fail-open: guard unavailable
        return 0

    # Throttle: only spend a judge call on risky (mutating) tools.
    if not sentinel.should_check(tool_name):
        _emit({"continue": True})
        return 0

    try:
        result = guard.sentinel_checkpoint(
            project,
            transcript=transcript,
            recent_action=_summarize_action(payload),
        )
    except Exception:
        _emit({"continue": True})  # fail-open: judge/model error
        return 0

    action = result.get("action")
    correction = result.get("correction") or ""
    problem = result.get("problem", "none")

    # PostToolUse's `decision: block` is model feedback, not an operator prompt.
    # L2 `ask` therefore stays in the feed and continues; only L3 correction or
    # escalation is injected back into the run. PreToolUse owns L2 approval.
    if action in ("correct", "escalate") and correction:
        tag = {"deception": "untruthful output", "intent_violation": "policy bypass",
               "drift": "goal drift"}.get(problem, "issue")
        prefix = f"[Goal Guard — {tag}] "
        _emit({"decision": "block", "reason": prefix + correction})
    else:
        _emit({"continue": True})
    return 0


if __name__ == "__main__":
    sys.exit(main())
