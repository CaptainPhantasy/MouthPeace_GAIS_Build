"""Configuration: trust level, recovery budget, and on-disk locations.

Level resolution order: GUARD_LEVEL env > .goalguard/config.json > default (0).
Everything lives under <project>/.goalguard so the guard is scoped and removable.
"""

from __future__ import annotations

import json
import os
from pathlib import Path

GUARD_DIRNAME = ".goalguard"

LEVEL_NAMES = {0: "shadow", 1: "suggest", 2: "ask", 3: "auto-correct"}


def guard_dir(project_dir: str | os.PathLike) -> Path:
    return Path(project_dir) / GUARD_DIRNAME


def _config_path(project_dir: str | os.PathLike) -> Path:
    return guard_dir(project_dir) / "config.json"


def load_config(project_dir: str | os.PathLike) -> dict:
    path = _config_path(project_dir)
    if path.exists():
        try:
            return json.loads(path.read_text())
        except json.JSONDecodeError:
            return {}
    return {}


def save_config(project_dir: str | os.PathLike, data: dict) -> None:
    gd = guard_dir(project_dir)
    gd.mkdir(parents=True, exist_ok=True)
    _config_path(project_dir).write_text(json.dumps(data, indent=2))


def get_level(project_dir: str | os.PathLike) -> int:
    env = os.getenv("GUARD_LEVEL")
    if env is not None and env.strip() != "":
        try:
            return max(0, min(3, int(env)))
        except ValueError:
            pass
    return max(0, min(3, int(load_config(project_dir).get("level", 0))))


def set_level(project_dir: str | os.PathLike, level: int) -> int:
    level = max(0, min(3, int(level)))
    cfg = load_config(project_dir)
    cfg["level"] = level
    save_config(project_dir, cfg)
    return level


def get_max_recoveries(project_dir: str | os.PathLike) -> int:
    env = os.getenv("GUARD_MAX_RECOVERIES")
    if env:
        try:
            return max(0, int(env))
        except ValueError:
            pass
    return int(load_config(project_dir).get("max_recoveries", 2))
