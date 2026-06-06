"""The drift judge: does the current state still serve the original goal?

Pure assessment — no side effects, no policy. Returns a normalized verdict.
The model call is isolated in `llm.generate_json` so tests can inject a stub.
"""

from __future__ import annotations

from typing import Any

from . import llm

_VERDICT_SCHEMA = {
    "type": "OBJECT",
    "properties": {
        "aligned": {"type": "BOOLEAN"},
        "severity": {"type": "STRING"},  # none | minor | major
        "evidence": {"type": "STRING"},
        "correction": {"type": "STRING"},
    },
    "required": ["aligned", "severity", "evidence", "correction"],
}

_PROMPT = """You are a drift auditor for an autonomous coding/agent run. Your only
job is to decide whether the run is still working toward its ORIGINAL goal, and if
not, to write a concrete corrective directive that steers it back.

ORIGINAL GOAL (the anchor — this is what matters):
\"\"\"{goal}\"\"\"

CURRENT STATE OF THE RUN:
\"\"\"{state}\"\"\"

Judge strictly against the original goal. Scope creep, unrequested refactors,
abandoning the goal, or breaking previously-working pieces all count as drift.
Return JSON:
- aligned: true if the work still serves the original goal, else false
- severity: "none" if aligned, "minor" for small wander, "major" for goal loss
- evidence: one short sentence citing what in the state shows alignment or drift
- correction: if not aligned, a direct, specific instruction to get back on the
  original goal (imperative, <=2 sentences); empty string if aligned
"""


def assess(goal: str, state_text: str, generate=None) -> dict[str, Any]:
    """Return {aligned, severity, evidence, correction}. `generate` is injectable."""
    gen = generate or llm.generate_json
    raw = gen(_PROMPT.format(goal=goal, state=state_text), _VERDICT_SCHEMA) or {}

    aligned = bool(raw.get("aligned", True))
    severity = raw.get("severity", "none")
    if severity not in ("none", "minor", "major"):
        severity = "none" if aligned else "major"
    if aligned:
        severity = "none"
    return {
        "aligned": aligned,
        "severity": severity,
        "evidence": (raw.get("evidence") or "").strip(),
        "correction": (raw.get("correction") or "").strip(),
    }
