"""The trust ladder — maps a verdict + level + recovery count to an Action.

L0 shadow: observe only (never injects). L1 suggest. L2 ask (needs approval).
L3 auto-correct, escalating once it can't recover within the budget. This is the
graduated-trust core: the guard only does what its level permits.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass
class Action:
    kind: str          # ok | observe | suggest | ask | correct | escalate
    correction: str    # the directive (empty when aligned)
    reason: str        # human-readable explanation for the feed
    severity: str      # none | minor | major
    level: int


def decide(verdict: dict, level: int, recovery_count: int, max_recoveries: int) -> Action:
    severity = verdict.get("severity", "none")
    correction = verdict.get("correction", "") or ""

    if verdict.get("aligned", True):
        return Action("ok", "", "On track toward the goal.", severity, level)

    # Drifting from here down.
    if level <= 0:
        return Action("observe", correction,
                      "Shadow mode: would inject this correction (no change made).",
                      severity, level)
    if level == 1:
        return Action("suggest", correction,
                      "Suggested correction — apply it yourself.", severity, level)
    if level == 2:
        return Action("ask", correction,
                      "Proposed correction — awaiting your approval.", severity, level)

    # level >= 3 (auto-correct + escalate)
    if recovery_count >= max_recoveries:
        return Action("escalate", correction,
                      f"Could not recover after {recovery_count} auto-correction(s).",
                      severity, level)
    return Action("correct", correction,
                  "Auto-correcting back toward the goal.", severity, level)
