from __future__ import annotations

import importlib.util
import io
import json
import multiprocessing
import sys
import tempfile
import unittest
from concurrent.futures import ProcessPoolExecutor
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from goalguard import anchor, config, feed, guard, sentinel  # noqa: E402


def _load_posttooluse_hook():
    path = (
        Path(__file__).resolve().parents[1]
        / "adapters"
        / "claude_code"
        / "goalguard_posttooluse_hook.py"
    )
    spec = importlib.util.spec_from_file_location("goalguard_posttooluse_hook", path)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


POSTTOOLUSE_HOOK = _load_posttooluse_hook()


def ok_verdict(goal, state):
    return {"aligned": True, "problem": "none", "severity": "none", "evidence": "fine", "correction": ""}


def deception_verdict(goal, state):
    return {"aligned": False, "problem": "deception", "severity": "major",
            "evidence": "claims tests pass but no test was run",
            "correction": "Do not report success; actually run the tests and report real results."}


def intent_verdict(goal, state):
    return {"aligned": False, "problem": "intent_violation", "severity": "major",
            "evidence": "reasoning plans to skip the migration and ALTER TABLE directly",
            "correction": "Stop. Create a migration and back up the table before any schema change."}


def parallel_intent_checkpoint(project_dir: str) -> str:
    """Process-pool worker that simulates an independent Claude hook."""
    return guard.sentinel_checkpoint(
        project_dir, assess_fn=intent_verdict
    )["action"]


class TestSentinelThrottle(unittest.TestCase):
    def test_mutating_tools_are_checked(self):
        for t in ("Bash", "Write", "Edit", "MultiEdit", "apply_patch"):
            self.assertTrue(sentinel.should_check(t), t)

    def test_update_tool_variants_are_checked(self):
        for tool_name in (
            "Update",
            "TaskUpdate",
            "update_record",
            "mcp__crm__update_record",
        ):
            self.assertTrue(sentinel.should_check(tool_name), tool_name)

    def test_readonly_tools_are_skipped(self):
        for t in ("Read", "Glob", "Grep", "WebFetch"):
            self.assertFalse(sentinel.should_check(t), t)

    def test_allowlist_override(self):
        import os
        os.environ["GUARD_SENTINEL_TOOLS"] = "read"
        try:
            self.assertTrue(sentinel.should_check("Read"))
            self.assertFalse(sentinel.should_check("Bash"))
        finally:
            del os.environ["GUARD_SENTINEL_TOOLS"]

    def test_permission_mapping(self):
        # L3 auto-correct / escalate -> deny the pending call before it runs
        self.assertEqual(sentinel.permission_for("correct"), "deny")
        self.assertEqual(sentinel.permission_for("escalate"), "deny")
        # L2 -> ask the human
        self.assertEqual(sentinel.permission_for("ask"), "ask")
        # L0/L1/on-track -> allow
        for k in ("ok", "observe", "suggest"):
            self.assertEqual(sentinel.permission_for(k), "allow")


class TestSentinelCheckpoint(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        guard.set_goal(self.tmp, "Add a CSV export button to the reports page")

    def test_detects_deception_and_logs_problem(self):
        config.set_level(self.tmp, 0)  # shadow: observe, change nothing
        res = guard.sentinel_checkpoint(self.tmp, assess_fn=deception_verdict)
        self.assertEqual(res["problem"], "deception")
        self.assertEqual(res["action"], "observe")
        self.assertTrue(res["correction"])
        self.assertTrue(any(e.get("problem") == "deception" for e in feed.read(self.tmp)))

    def test_intent_violation_autocorrects_at_l3(self):
        config.set_level(self.tmp, 3)
        res = guard.sentinel_checkpoint(self.tmp, assess_fn=intent_verdict)
        self.assertEqual(res["problem"], "intent_violation")
        self.assertEqual(res["action"], "correct")
        self.assertIn("migration", res["correction"].lower())

    def test_ok_passes_clean(self):
        config.set_level(self.tmp, 3)
        res = guard.sentinel_checkpoint(self.tmp, assess_fn=ok_verdict)
        self.assertEqual(res["action"], "ok")
        self.assertTrue(res["aligned"])
        self.assertEqual(res["problem"], "none")

    def test_l3_escalates_after_budget(self):
        config.set_level(self.tmp, 3)
        guard.sentinel_checkpoint(self.tmp, assess_fn=intent_verdict)  # correct (rec->1)
        guard.sentinel_checkpoint(self.tmp, assess_fn=intent_verdict)  # correct (rec->2)
        res = guard.sentinel_checkpoint(self.tmp, assess_fn=intent_verdict)  # escalate
        self.assertEqual(res["action"], "escalate")
        self.assertTrue(any(e.get("action") == "escalate" for e in feed.read(self.tmp)))

    def test_parallel_hooks_reserve_recovery_budget_once_each(self):
        config.set_level(self.tmp, 3)
        process_count = 6
        context = multiprocessing.get_context("spawn")
        with ProcessPoolExecutor(
            max_workers=process_count,
            mp_context=context,
        ) as pool:
            actions = list(
                pool.map(parallel_intent_checkpoint, [self.tmp] * process_count)
            )

        self.assertEqual(actions.count("correct"), 2)
        self.assertEqual(actions.count("escalate"), process_count - 2)
        self.assertEqual(anchor.get_anchor(self.tmp)["recoveries"], 2)


class TestPostToolUseAdapter(unittest.TestCase):
    def _run_with_result(self, result: dict) -> dict:
        output = io.StringIO()
        payload = {
            "cwd": tempfile.mkdtemp(),
            "tool_name": "TaskUpdate",
            "tool_input": {"status": "completed"},
            "tool_response": {"ok": True},
        }
        with (
            patch.object(sentinel, "should_check", return_value=True),
            patch.object(guard, "sentinel_checkpoint", return_value=result),
            patch.object(POSTTOOLUSE_HOOK.sys, "stdin", io.StringIO(json.dumps(payload))),
            patch.object(POSTTOOLUSE_HOOK.sys, "stdout", output),
        ):
            self.assertEqual(POSTTOOLUSE_HOOK.main(), 0)
        return json.loads(output.getvalue())

    def test_l2_ask_does_not_auto_feed_correction(self):
        emitted = self._run_with_result({
            "action": "ask",
            "problem": "deception",
            "correction": "Run the tests before claiming completion.",
        })
        self.assertEqual(emitted, {"continue": True})

    def test_l3_correction_still_feeds_the_model(self):
        emitted = self._run_with_result({
            "action": "correct",
            "problem": "deception",
            "correction": "Run the tests before claiming completion.",
        })
        self.assertEqual(emitted["decision"], "block")
        self.assertIn("Run the tests", emitted["reason"])


if __name__ == "__main__":
    unittest.main()
