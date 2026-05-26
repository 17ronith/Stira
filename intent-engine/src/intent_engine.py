"""
intent_engine.py — Entry point for the Stira intent engine.

parse_intent(raw_text) calls qwen3:8b via Ollama with constrained JSON decoding
(Ollama `format` parameter) and returns a validated StiraPolicy dataclass.
"""

from __future__ import annotations

import json
from dataclasses import dataclass

import requests
import jsonschema

from src.stira_policy import StiraPolicy
from src.prompt_builder import build_prompt, load_schema


# ---------------------------------------------------------------------------
# Error type
# ---------------------------------------------------------------------------

@dataclass
class IntentError(Exception):
    """Raised when the intent engine cannot produce a valid policy."""
    code: str          # "api_failure" | "parse_failure" | "schema_violation"
    message: str
    raw_response: str | None = None


# ---------------------------------------------------------------------------
# Public API
# ---------------------------------------------------------------------------

def parse_intent(
    raw_text: str,
    ollama_url: str = "http://localhost:11434",
) -> StiraPolicy:
    """
    Convert natural language intent to a validated StiraPolicy.

    Args:
        raw_text:   The user's raw intent string.
        ollama_url: Base URL of the Ollama server.

    Returns:
        A StiraPolicy dataclass instance.

    Raises:
        IntentError with code "api_failure"      — network / server error.
        IntentError with code "parse_failure"    — response is not valid JSON.
        IntentError with code "schema_violation" — JSON does not match schema.
    """
    prompt = build_prompt(raw_text)
    schema = load_schema()

    payload = {
        "model": "qwen3:8b",
        "prompt": prompt,
        "format": schema,
        "stream": False,
    }

    # --- 1. API call --------------------------------------------------------
    try:
        response = requests.post(
            f"{ollama_url}/api/generate",
            json=payload,
            timeout=30,
        )
    except Exception as exc:
        raise IntentError(
            code="api_failure",
            message=str(exc),
        ) from exc

    # --- 2. Extract and parse JSON response --------------------------------
    raw_response: str = response.json()["response"]

    try:
        policy_dict = json.loads(raw_response)
    except json.JSONDecodeError as exc:
        raise IntentError(
            code="parse_failure",
            message=f"Response is not valid JSON: {exc}",
            raw_response=raw_response,
        ) from exc

    # --- 3. Validate against schema ----------------------------------------
    try:
        jsonschema.validate(policy_dict, schema)
    except jsonschema.ValidationError as exc:
        raise IntentError(
            code="schema_violation",
            message=str(exc),
            raw_response=raw_response,
        ) from exc

    # --- 4. Deserialise into dataclass -------------------------------------
    return StiraPolicy.from_dict(policy_dict)
