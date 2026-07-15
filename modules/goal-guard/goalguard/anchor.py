"""The goal anchor — the single source of truth a run is judged against.

Stored at <project>/.goalguard/anchor.json. Also tracks `recoveries`, the count
of consecutive drifting checkpoints that auto-correct has attempted, used to
decide when to escalate.
"""

from __future__ import annotations

import json
import os
import tempfile
from contextlib import contextmanager
from datetime import datetime, timezone
from fcntl import LOCK_EX, LOCK_SH, LOCK_UN, flock
from pathlib import Path
from typing import Iterator, Optional, TextIO

from .config import guard_dir


def _anchor_path(project_dir: str | os.PathLike) -> Path:
    return guard_dir(project_dir) / "anchor.json"


def _lock_path(project_dir: str | os.PathLike) -> Path:
    return guard_dir(project_dir) / "anchor.lock"


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()


@contextmanager
def _anchor_lock(
    project_dir: str | os.PathLike,
    *,
    shared: bool = False,
) -> Iterator[TextIO]:
    """Serialize anchor access across independent hook processes."""
    gd = guard_dir(project_dir)
    gd.mkdir(parents=True, exist_ok=True)
    with _lock_path(project_dir).open("a+") as lock_file:
        flock(lock_file.fileno(), LOCK_SH if shared else LOCK_EX)
        try:
            yield lock_file
        finally:
            flock(lock_file.fileno(), LOCK_UN)


def _read_anchor_unlocked(project_dir: str | os.PathLike) -> Optional[dict]:
    path = _anchor_path(project_dir)
    if not path.exists():
        return None
    try:
        return json.loads(path.read_text())
    except (json.JSONDecodeError, OSError):
        return None


def _write_anchor_unlocked(project_dir: str | os.PathLike, data: dict) -> None:
    """Atomically replace anchor.json while the caller holds the anchor lock."""
    gd = guard_dir(project_dir)
    gd.mkdir(parents=True, exist_ok=True)
    tmp_path: Optional[Path] = None
    try:
        with tempfile.NamedTemporaryFile(
            "w",
            encoding="utf-8",
            dir=gd,
            prefix="anchor.",
            suffix=".tmp",
            delete=False,
        ) as tmp:
            json.dump(data, tmp, indent=2)
            tmp.write("\n")
            tmp.flush()
            os.fsync(tmp.fileno())
            tmp_path = Path(tmp.name)
        os.replace(tmp_path, _anchor_path(project_dir))
        tmp_path = None
    finally:
        if tmp_path is not None:
            tmp_path.unlink(missing_ok=True)


def set_goal(project_dir: str | os.PathLike, goal: str, run_id: Optional[str] = None) -> dict:
    data = {
        "goal": (goal or "").strip(),
        "created_at": _now(),
        "run_id": run_id or datetime.now(timezone.utc).strftime("run-%Y%m%d-%H%M%S"),
        "recoveries": 0,
    }
    with _anchor_lock(project_dir):
        _write_anchor_unlocked(project_dir, data)
    return data


def get_anchor(project_dir: str | os.PathLike) -> Optional[dict]:
    path = _anchor_path(project_dir)
    if not path.exists():
        return None
    with _anchor_lock(project_dir, shared=True):
        return _read_anchor_unlocked(project_dir)


def set_recoveries(project_dir: str | os.PathLike, count: int) -> None:
    with _anchor_lock(project_dir):
        anchor = _read_anchor_unlocked(project_dir)
        if anchor is None:
            return
        anchor["recoveries"] = max(0, int(count))
        _write_anchor_unlocked(project_dir, anchor)


def transition_recoveries(
    project_dir: str | os.PathLike,
    *,
    aligned: bool,
    auto_correct: bool,
    max_recoveries: int,
) -> int:
    """Atomically reserve a recovery slot and return the prior count.

    Parallel PostToolUse hooks must make the ladder decision from a unique,
    serialized counter value. Returning the prior value preserves
    ``ladder.decide`` semantics: values below the budget correct, while a value
    at the budget escalates without incrementing again.
    """
    with _anchor_lock(project_dir):
        anchor = _read_anchor_unlocked(project_dir)
        if anchor is None:
            return 0

        current = max(0, int(anchor.get("recoveries", 0)))
        next_count = current
        if aligned:
            next_count = 0
        elif auto_correct and current < max(0, int(max_recoveries)):
            next_count = current + 1

        if next_count != current:
            anchor["recoveries"] = next_count
            _write_anchor_unlocked(project_dir, anchor)
        return current


def clear(project_dir: str | os.PathLike) -> None:
    with _anchor_lock(project_dir):
        path = _anchor_path(project_dir)
        if path.exists():
            path.unlink()
