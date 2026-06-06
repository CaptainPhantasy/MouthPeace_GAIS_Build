"""Model-agnostic judge backend.

The drift judge needs a model, but Goal Guard has no allegiance to one. Provider
resolution: GUARD_LLM_PROVIDER > AGENT_LLM_PROVIDER > "gemini". Gemini uses native
structured output; GLM/MiniMax/custom go through LiteLLM's OpenAI-compatible API.
Swap the judge by changing one env var — no code change.
"""

from __future__ import annotations

import json
import os
import re
from typing import Any

_PROVIDERS: dict[str, dict[str, str]] = {
    "glm": {"model": "glm-4.6", "api_base": "https://api.z.ai/api/coding/paas/v4",
            "base_env": "ZAI_API_BASE", "key_env": "ZAI_API_KEY"},
    "zai": {"model": "glm-4.6", "api_base": "https://api.z.ai/api/coding/paas/v4",
            "base_env": "ZAI_API_BASE", "key_env": "ZAI_API_KEY"},
    "minimax": {"model": "MiniMax-M2", "api_base": "https://api.minimax.io/v1",
                "base_env": "MINIMAX_API_BASE", "key_env": "MINIMAX_API_KEY"},
}


def provider() -> str:
    return (os.getenv("GUARD_LLM_PROVIDER") or os.getenv("AGENT_LLM_PROVIDER") or "gemini").strip().lower()


def _litellm_target() -> tuple[str, str, str]:
    p = provider()
    if p in _PROVIDERS:
        cfg = _PROVIDERS[p]
        return (os.getenv("GUARD_LLM_MODEL", cfg["model"]),
                os.getenv(cfg["base_env"], cfg["api_base"]),
                os.environ[cfg["key_env"]])
    return (os.environ["GUARD_LLM_MODEL"],
            os.environ["GUARD_LLM_API_BASE"],
            os.environ["GUARD_LLM_API_KEY"])


def extract_json(text: str) -> Any:
    if not text:
        return None
    fenced = re.search(r"```(?:json)?\s*(.*?)```", text, re.DOTALL)
    candidate = fenced.group(1).strip() if fenced else text.strip()
    try:
        return json.loads(candidate)
    except json.JSONDecodeError:
        pass
    for opener, closer in (("{", "}"), ("[", "]")):
        start, end = candidate.find(opener), candidate.rfind(closer)
        if start != -1 and end > start:
            try:
                return json.loads(candidate[start:end + 1])
            except json.JSONDecodeError:
                continue
    return None


def generate_json(prompt: str, schema: dict[str, Any], temperature: float = 0.1) -> Any:
    """Return a parsed JSON object from the active provider."""
    if provider() in ("", "gemini", "google"):
        from google import genai
        from google.genai import types

        key = os.getenv("GOOGLE_API_KEY") or os.getenv("GEMINI_API_KEY")
        if not key:
            raise RuntimeError("GOOGLE_API_KEY is not set (required for the Gemini judge).")
        client = genai.Client(api_key=key)
        resp = client.models.generate_content(
            model=os.getenv("GUARD_LLM_MODEL", "gemini-2.5-flash"),
            contents=prompt,
            config=types.GenerateContentConfig(
                response_mime_type="application/json",
                response_schema=schema,
                temperature=temperature,
            ),
        )
        return json.loads(resp.text)

    import litellm

    model, api_base, api_key = _litellm_target()
    resp = litellm.completion(
        model=f"openai/{model}",
        api_base=api_base,
        api_key=api_key,
        messages=[{"role": "user", "content": prompt + "\n\nRespond with ONLY one valid JSON object."}],
        response_format={"type": "json_object"},
        temperature=temperature,
    )
    return extract_json(resp.choices[0].message.content or "")
