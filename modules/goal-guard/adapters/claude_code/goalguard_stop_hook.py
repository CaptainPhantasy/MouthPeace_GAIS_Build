#!/usr/bin/env python3
"""Coding-agent Stop-hook adapter for Goal Guard.

The coding agent invokes this when a run is about to stop. It runs one Goal Guard
checkpoint and, at trust levels that permit it (L2/L3), blocks the stop and feeds
the correction back so the run realigns to the goal. At L0/L1 it never blocks —
it only observes/suggests (the checkpoint is still logged to the feed).

FAIL-OPEN: if anything goes wrong (guard not importable, judge error), it allows
the stop. The guard must never wedge your run.

Wire it up in the harness hook configuration (.claude/settings.json or equivalent):

    {
      "hooks": {
        "Stop": [
          { "hooks": [ { "type": "command",
              "command": "python3 /absolute/path/to/goal-guard/adapters/claude_code/goalguard_stop_hook.py" } ] }
        ]
      }
    }

Anchor a goal first:  goalguard set "the goal" --project /your/project
"""

from __future__ import annotations

import json
import os
import sys


def _emit(obj: dict) -> None:
    sys.stdout.write(json.dumps(obj))
    sys.stdout.flush()


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        payload = {}

    project = payload.get("cwd") or os.getcwd()
    transcript = payload.get("transcript_path")

    # Avoid infinite loops: if we already blocked once this stop, let it pass.
    if payload.get("stop_hook_active"):
        _emit({"continue": True})
        return 0

    try:
        from goalguard import guard
    except Exception:
        _emit({"continue": True})  # fail-open: guard unavailable
        return 0

    try:
        result = guard.checkpoint(project, transcript=transcript)
    except Exception:
        _emit({"continue": True})  # fail-open: judge/model error
        return 0

    action = result.get("action")
    correction = result.get("correction") or ""

    # Only L2/L3 outcomes carry an actionable correction back into the run.
    if action in ("correct", "ask", "escalate") and correction:
        prefix = "[Goal Guard] " if action != "ask" else "[Goal Guard — approve to proceed] "
        _emit({"decision": "block", "reason": prefix + correction})
    else:
        _emit({"continue": True})
    return 0


if __name__ == "__main__":
    sys.exit(main())
