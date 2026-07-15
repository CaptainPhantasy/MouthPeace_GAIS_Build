from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from goalguard import anchor, config, feed, guard, sentinel  # noqa: E402


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


class TestSentinelThrottle(unittest.TestCase):
    def test_mutating_tools_are_checked(self):
        for t in ("Bash", "Write", "Edit", "MultiEdit", "apply_patch"):
            self.assertTrue(sentinel.should_check(t), t)

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


if __name__ == "__main__":
    unittest.main()
