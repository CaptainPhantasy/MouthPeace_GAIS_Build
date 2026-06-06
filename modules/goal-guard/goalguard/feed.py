"""The feed — the one visible artifact of an otherwise invisible guardian.

Append-only JSONL at <project>/.goalguard/feed.jsonl, plus a human-readable
render for `goalguard feed`. This is how you watch it work and decide whether to
promote it up the trust ladder.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path

from .config import guard_dir

_ICON = {
    "goal_set": "🎯",
    "ok": "✅",
    "observe": "👁️ ",
    "suggest": "💡",
    "ask": "🙋",
    "correct": "🔧",
    "escalate": "🚨",
}


def _feed_path(project_dir: str | os.PathLike) -> Path:
    return guard_dir(project_dir) / "feed.jsonl"


def record(project_dir: str | os.PathLike, event: dict) -> dict:
    gd = guard_dir(project_dir)
    gd.mkdir(parents=True, exist_ok=True)
    entry = {"ts": datetime.now(timezone.utc).isoformat(), **event}
    with open(_feed_path(project_dir), "a") as f:
        f.write(json.dumps(entry) + "\n")
    return entry


def read(project_dir: str | os.PathLike, limit: int = 20) -> list[dict]:
    path = _feed_path(project_dir)
    if not path.exists():
        return []
    lines = path.read_text().splitlines()
    out = []
    for line in lines[-limit:]:
        try:
            out.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return out


def render(project_dir: str | os.PathLike, limit: int = 20) -> str:
    events = read(project_dir, limit)
    if not events:
        return "(no Goal Guard activity yet)"
    rows = []
    for e in events:
        ts = e.get("ts", "")[11:19]
        kind = e.get("action") or e.get("type", "?")
        icon = _ICON.get(kind, "•")
        line = f"{ts} {icon} {kind}"
        if e.get("type") == "goal_set":
            line += f"  goal: {e.get('goal','')[:80]}"
        else:
            sev = e.get("severity")
            if sev and sev != "none":
                line += f"  [{sev}]"
            if e.get("evidence"):
                line += f"\n        why: {e['evidence'][:160]}"
            if e.get("correction") and kind not in ("ok",):
                line += f"\n        fix: {e['correction'][:160]}"
        rows.append(line)
    return "\n".join(rows)
