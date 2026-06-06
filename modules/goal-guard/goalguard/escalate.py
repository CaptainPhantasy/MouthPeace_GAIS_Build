"""Escalation — the only time the guardian reaches out to you.

Always records an escalate event to the feed. Optionally runs GUARD_NOTIFY_CMD
(any shell command — ntfy/Pushover/Pushcut/etc., with $GUARD_MESSAGE set) and,
if GUARD_MACOS_NOTIFY is truthy, shows a macOS banner. Best-effort and never
raises — escalation must not crash the run it is guarding.
"""

from __future__ import annotations

import os
import subprocess

from . import feed


def notify(project_dir, action, anchor: dict) -> str:
    goal = (anchor or {}).get("goal", "")
    message = f"[Goal Guard] Drift unrecovered on goal '{goal[:60]}': {action.reason}"

    feed.record(project_dir, {
        "type": "escalate",
        "action": "escalate",
        "severity": action.severity,
        "message": message,
        "correction": action.correction,
    })

    cmd = os.getenv("GUARD_NOTIFY_CMD")
    if cmd:
        # `cmd` is operator-authored configuration (like a git hook), so shell=True
        # is intentional. The only dynamic/untrusted data (goal text, model output)
        # is delivered via the GUARD_MESSAGE env var and is NEVER concatenated into
        # the command string, so it cannot inject shell commands.
        try:
            subprocess.run(cmd, shell=True, timeout=20,  # noqa: S602 (see note above)
                           env={**os.environ, "GUARD_MESSAGE": message})
        except Exception:
            pass

    if os.getenv("GUARD_MACOS_NOTIFY", "").lower() in ("1", "true", "yes"):
        try:
            safe = message.replace('"', "'")
            subprocess.run(
                ["osascript", "-e", f'display notification "{safe}" with title "Goal Guard"'],
                timeout=10,
            )
        except Exception:
            pass

    return message
