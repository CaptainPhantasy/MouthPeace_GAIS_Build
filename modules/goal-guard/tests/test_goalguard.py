from __future__ import annotations

import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))

from goalguard import anchor, config, feed, guard, ladder  # noqa: E402


def aligned_verdict(goal, state):
    return {"aligned": True, "severity": "none", "evidence": "matches goal", "correction": ""}


def drift_verdict(goal, state):
    return {"aligned": False, "severity": "major",
            "evidence": "wandered into an unrelated refactor",
            "correction": "Stop the refactor and return to the original goal."}


class TestAnchorAndFeed(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()

    def test_set_and_get_goal(self):
        guard.set_goal(self.tmp, "Build the login page")
        a = anchor.get_anchor(self.tmp)
        self.assertEqual(a["goal"], "Build the login page")
        self.assertEqual(a["recoveries"], 0)
        # goal_set is recorded on the feed
        self.assertTrue(any(e.get("type") == "goal_set" for e in feed.read(self.tmp)))

    def test_no_anchor_is_noop(self):
        res = guard.checkpoint(self.tmp, assess_fn=drift_verdict)
        self.assertEqual(res["action"], "ok")
        self.assertTrue(res["aligned"])


class TestLadder(unittest.TestCase):
    def test_aligned_is_ok_at_every_level(self):
        v = {"aligned": True, "severity": "none", "correction": ""}
        for lvl in range(4):
            self.assertEqual(ladder.decide(v, lvl, 0, 2).kind, "ok")

    def test_drift_maps_to_level(self):
        v = {"aligned": False, "severity": "major", "correction": "fix it"}
        self.assertEqual(ladder.decide(v, 0, 0, 2).kind, "observe")
        self.assertEqual(ladder.decide(v, 1, 0, 2).kind, "suggest")
        self.assertEqual(ladder.decide(v, 2, 0, 2).kind, "ask")
        self.assertEqual(ladder.decide(v, 3, 0, 2).kind, "correct")

    def test_escalates_after_budget(self):
        v = {"aligned": False, "severity": "major", "correction": "fix it"}
        self.assertEqual(ladder.decide(v, 3, 2, 2).kind, "escalate")


class TestGuardCheckpoint(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp()
        guard.set_goal(self.tmp, "Implement CSV export")

    def test_shadow_never_changes_anything(self):
        config.set_level(self.tmp, 0)
        res = guard.checkpoint(self.tmp, assess_fn=drift_verdict)
        self.assertEqual(res["action"], "observe")
        self.assertTrue(res["correction"])  # the would-be fix is logged
        # recovery counter stays 0 in shadow (we never auto-correct)
        self.assertEqual(anchor.get_anchor(self.tmp)["recoveries"], 0)

    def test_level3_autocorrects_then_escalates(self):
        config.set_level(self.tmp, 3)
        # max_recoveries default = 2 → two corrects, then escalate
        r1 = guard.checkpoint(self.tmp, assess_fn=drift_verdict)
        r2 = guard.checkpoint(self.tmp, assess_fn=drift_verdict)
        r3 = guard.checkpoint(self.tmp, assess_fn=drift_verdict)
        self.assertEqual(r1["action"], "correct")
        self.assertEqual(r2["action"], "correct")
        self.assertEqual(r3["action"], "escalate")
        # an escalate event lands on the feed
        self.assertTrue(any(e.get("action") == "escalate" for e in feed.read(self.tmp)))

    def test_recovery_counter_resets_on_realignment(self):
        config.set_level(self.tmp, 3)
        guard.checkpoint(self.tmp, assess_fn=drift_verdict)   # recoveries -> 1
        self.assertEqual(anchor.get_anchor(self.tmp)["recoveries"], 1)
        guard.checkpoint(self.tmp, assess_fn=aligned_verdict)  # back on track -> 0
        self.assertEqual(anchor.get_anchor(self.tmp)["recoveries"], 0)


if __name__ == "__main__":
    unittest.main()
