"""Capture the current state of a run, harness-agnostically.

Signals are deliberately generic so this works regardless of which tool/model is
driving: git working-tree changes, plus an optional transcript tail and a free
-text 'activity' the adapter can pass. No harness internals required.
"""

from __future__ import annotations

import os
import subprocess
from pathlib import Path
from typing import Optional


def _git(project_dir: str | os.PathLike, args: list[str]) -> str:
    try:
        out = subprocess.run(
            ["git", "-C", str(project_dir), *args],
            capture_output=True, text=True, timeout=15,
        )
        return out.stdout.strip()
    except Exception:
        return ""


def capture(
    project_dir: str | os.PathLike,
    transcript: Optional[str] = None,
    activity: Optional[str] = None,
    max_transcript_chars: int = 4000,
) -> dict:
    changed = _git(project_dir, ["status", "--short"])
    diffstat = _git(project_dir, ["diff", "--stat"])
    recent_commits = _git(project_dir, ["log", "--oneline", "-5"])

    tail = ""
    if transcript:
        p = Path(transcript)
        if p.exists():
            try:
                tail = p.read_text(errors="ignore")[-max_transcript_chars:]
            except Exception:
                tail = ""

    return {
        "changed_files": changed,
        "diffstat": diffstat,
        "recent_commits": recent_commits,
        "transcript_tail": tail,
        "activity": activity or "",
    }


def to_text(summary: dict) -> str:
    parts = []
    if summary.get("activity"):
        parts.append(f"## Stated current activity\n{summary['activity']}")
    if summary.get("changed_files"):
        parts.append(f"## Working-tree changes (git status)\n{summary['changed_files']}")
    if summary.get("diffstat"):
        parts.append(f"## Diff stat\n{summary['diffstat']}")
    if summary.get("recent_commits"):
        parts.append(f"## Recent commits\n{summary['recent_commits']}")
    if summary.get("transcript_tail"):
        parts.append(f"## Tail of run transcript/log\n{summary['transcript_tail']}")
    if not parts:
        return "(no observable state — empty working tree, no transcript provided)"
    return "\n\n".join(parts)
