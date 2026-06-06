"""The goal anchor — the single source of truth a run is judged against.

Stored at <project>/.goalguard/anchor.json. Also tracks `recoveries`, the count
of consecutive drifting checkpoints that auto-correct has attempted, used to
decide when to escalate.
"""

from __future__ import annotations

import json
import os
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

from .config import guard_dir


def _anchor_path(project_dir: str | os.PathLike) -> Path:
    return guard_dir(project_dir) / "anchor.json"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


def set_goal(project_dir: str | os.PathLike, goal: str, run_id: Optional[str] = None) -> dict:
    gd = guard_dir(project_dir)
    gd.mkdir(parents=True, exist_ok=True)
    data = {
        "goal": (goal or "").strip(),
        "created_at": _now(),
        "run_id": run_id or datetime.now(timezone.utc).strftime("run-%Y%m%d-%H%M%S"),
        "recoveries": 0,
    }
    _anchor_path(project_dir).write_text(json.dumps(data, indent=2))
    return data


def get_anchor(project_dir: str | os.PathLike) -> Optional[dict]:
    path = _anchor_path(project_dir)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except json.JSONDecodeError:
        return None


def set_recoveries(project_dir: str | os.PathLike, count: int) -> None:
    anchor = get_anchor(project_dir)
    if anchor is None:
        return
    anchor["recoveries"] = max(0, int(count))
    _anchor_path(project_dir).write_text(json.dumps(anchor, indent=2))


def clear(project_dir: str | os.PathLike) -> None:
    path = _anchor_path(project_dir)
    if path.exists():
        path.unlink()
