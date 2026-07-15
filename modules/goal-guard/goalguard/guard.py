"""Orchestrator — ties anchor → state → judge → ladder → feed → escalate.

`checkpoint()` is the single entry point an adapter calls. It returns a plain
dict describing the decision; the adapter decides whether/how to inject the
correction based on `action`. The model judge is injectable for testing.
"""

from __future__ import annotations

import os
from typing import Callable, Optional

from . import anchor, config, escalate, feed, judge, ladder, state


def _decide_and_transition_recoveries(
    project_dir,
    verdict: dict,
    level: int,
    max_recoveries: int,
) -> ladder.Action:
    """Make recovery-budget decisions safely across parallel hook processes."""
    aligned = bool(verdict.get("aligned", True))
    recoveries = anchor.transition_recoveries(
        project_dir,
        aligned=aligned,
        auto_correct=not aligned and level >= 3,
        max_recoveries=max_recoveries,
    )
    return ladder.decide(verdict, level, recoveries, max_recoveries)


def set_goal(project_dir, goal: str, run_id: Optional[str] = None) -> dict:
    data = anchor.set_goal(project_dir, goal, run_id)
    feed.record(project_dir, {"type": "goal_set", "action": "goal_set",
                              "goal": data["goal"], "run_id": data["run_id"]})
    return data


def checkpoint(
    project_dir,
    transcript: Optional[str] = None,
    activity: Optional[str] = None,
    assess_fn: Optional[Callable[[str, str], dict]] = None,
) -> dict:
    """Run one drift checkpoint. Returns a dict with at least `action` and `correction`."""
    a = anchor.get_anchor(project_dir)
    level = config.get_level(project_dir)
    if a is None:
        return {"action": "ok", "reason": "No goal anchored; nothing to guard.",
                "aligned": True, "correction": "", "severity": "none", "level": level}

    max_recoveries = config.get_max_recoveries(project_dir)
    summary = state.capture(project_dir, transcript=transcript, activity=activity)
    state_text = state.to_text(summary)

    assess = assess_fn or judge.assess
    verdict = assess(a["goal"], state_text)

    action = _decide_and_transition_recoveries(
        project_dir, verdict, level, max_recoveries
    )

    event = {
        "type": "checkpoint",
        "action": action.kind,
        "severity": action.severity,
        "level": level,
        "aligned": verdict.get("aligned", True),
        "evidence": verdict.get("evidence", ""),
        "correction": action.correction,
        "reason": action.reason,
    }
    feed.record(project_dir, event)

    if action.kind == "escalate":
        escalate.notify(project_dir, action, a)

    return event


def sentinel_checkpoint(
    project_dir,
    transcript: Optional[str] = None,
    recent_action: Optional[str] = None,
    activity: Optional[str] = None,
    assess_fn: Optional[Callable[[str, str], dict]] = None,
) -> dict:
    """Mid-run check for drift OR deception OR intent-to-violate.

    `recent_action` is a short description of the tool call that just ran (name +
    input/result), folded into the judged state. Returns a dict with `action`,
    `problem`, and `correction`.
    """
    a = anchor.get_anchor(project_dir)
    level = config.get_level(project_dir)
    if a is None:
        return {"action": "ok", "problem": "none", "reason": "No goal anchored.",
                "aligned": True, "correction": "", "severity": "none", "level": level}

    max_recoveries = config.get_max_recoveries(project_dir)
    summary = state.capture(project_dir, transcript=transcript, activity=activity)
    state_text = state.to_text(summary)
    if recent_action:
        state_text = f"## Most recent tool call\n{recent_action}\n\n{state_text}"

    assess = assess_fn or judge.sentinel_assess
    verdict = assess(a["goal"], state_text)

    action = _decide_and_transition_recoveries(
        project_dir, verdict, level, max_recoveries
    )

    event = {
        "type": "sentinel",
        "action": action.kind,
        "problem": verdict.get("problem", "none"),
        "severity": action.severity,
        "level": level,
        "aligned": verdict.get("aligned", True),
        "evidence": verdict.get("evidence", ""),
        "correction": action.correction,
        "reason": action.reason,
    }
    feed.record(project_dir, event)

    if action.kind == "escalate":
        escalate.notify(project_dir, action, a)

    return event
