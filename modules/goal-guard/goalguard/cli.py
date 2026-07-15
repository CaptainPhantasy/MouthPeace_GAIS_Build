"""Command-line interface: goalguard set|checkpoint|feed|level|status|reset.

`checkpoint` prints the decision as JSON (so adapters can parse it). Everything
else is for you: anchoring a goal, reading the feed, and moving the trust level.
"""

from __future__ import annotations

import argparse
import json
import os

from . import anchor, config, feed, guard


def _project(args) -> str:
    return args.project or os.getcwd()


def cmd_set(args) -> int:
    data = guard.set_goal(_project(args), args.goal)
    print(f"🎯 Goal anchored (run {data['run_id']}):\n   {data['goal']}")
    print(f"   Trust level: L{config.get_level(_project(args))} "
          f"({config.LEVEL_NAMES[config.get_level(_project(args))]})")
    return 0


def cmd_checkpoint(args) -> int:
    result = guard.checkpoint(_project(args), transcript=args.transcript, activity=args.activity)
    print(json.dumps(result))
    return 0


def cmd_sentinel(args) -> int:
    result = guard.sentinel_checkpoint(
        _project(args),
        transcript=args.transcript,
        recent_action=args.action,
        activity=args.activity,
    )
    print(json.dumps(result))
    return 0


def cmd_feed(args) -> int:
    print(feed.render(_project(args), limit=args.limit))
    return 0


def cmd_level(args) -> int:
    project = _project(args)
    if args.value is None:
        lvl = config.get_level(project)
        print(f"L{lvl} ({config.LEVEL_NAMES[lvl]})")
    else:
        lvl = config.set_level(project, args.value)
        print(f"Trust level set to L{lvl} ({config.LEVEL_NAMES[lvl]})")
    return 0


def cmd_status(args) -> int:
    project = _project(args)
    a = anchor.get_anchor(project)
    lvl = config.get_level(project)
    print(f"Project: {project}")
    print(f"Trust level: L{lvl} ({config.LEVEL_NAMES[lvl]})")
    if a:
        print(f"Goal: {a['goal']}")
        print(f"Run: {a['run_id']} | consecutive un-recovered drifts: {a.get('recoveries', 0)}")
    else:
        print("Goal: (none anchored — run `goalguard set \"<goal>\"`)")
    return 0


def cmd_reset(args) -> int:
    anchor.clear(_project(args))
    print("Anchor cleared.")
    return 0


def build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(prog="goalguard", description="Headless goal-drift guardian.")
    p.add_argument("--project", help="Project directory (default: cwd).")
    sub = p.add_subparsers(dest="command", required=True)

    s = sub.add_parser("set", help="Anchor the original goal for this run.")
    s.add_argument("goal")
    s.set_defaults(func=cmd_set)

    c = sub.add_parser("checkpoint", help="Run one drift checkpoint (prints JSON).")
    c.add_argument("--transcript", help="Path to a run transcript/log to sample.")
    c.add_argument("--activity", help="Free-text description of current activity.")
    c.set_defaults(func=cmd_checkpoint)

    se = sub.add_parser("sentinel", help="Run one mid-run sentinel check (drift/deception/intent).")
    se.add_argument("--transcript", help="Path to a run transcript/log to sample.")
    se.add_argument("--action", help="Short description of the tool call that just ran.")
    se.add_argument("--activity", help="Free-text description of current activity.")
    se.set_defaults(func=cmd_sentinel)

    f = sub.add_parser("feed", help="Show recent Goal Guard activity.")
    f.add_argument("--limit", type=int, default=20)
    f.set_defaults(func=cmd_feed)

    lv = sub.add_parser("level", help="Get or set the trust level (0-3).")
    lv.add_argument("value", nargs="?", type=int)
    lv.set_defaults(func=cmd_level)

    st = sub.add_parser("status", help="Show goal, level, and recovery state.")
    st.set_defaults(func=cmd_status)

    r = sub.add_parser("reset", help="Clear the anchored goal.")
    r.set_defaults(func=cmd_reset)
    return p


def main(argv=None) -> int:
    args = build_parser().parse_args(argv)
    return args.func(args)
