"""
prompt_builder.py — Constructs the Ollama prompt for the Stira intent engine.

Two public functions:
  load_schema() -> dict
  build_prompt(raw_intent: str) -> str
"""

from __future__ import annotations

import json
from pathlib import Path


# ---------------------------------------------------------------------------
# Schema loader
# ---------------------------------------------------------------------------

def load_schema() -> dict:
    """Read and return the parsed JSON Schema for StiraPolicy."""
    schema_path = Path(__file__).parent.parent.parent / "docs" / "schema" / "stira-policy.schema.json"
    with open(schema_path, "r", encoding="utf-8") as f:
        return json.load(f)


# ---------------------------------------------------------------------------
# Bundle ID lookup table (hardcoded)
# ---------------------------------------------------------------------------

BUNDLE_ID_TABLE = """\
App name → Bundle ID lookup table:
  twitter/x        → com.twitter.twitter
  instagram        → com.burbn.instagram
  slack            → com.tinyspeck.slackmacgap
  discord          → com.hnc.Discord
  messages         → com.apple.iMessage
  mail             → com.apple.mail
  youtube          → com.google.YouTube
  netflix          → com.netflix.Netflix
  tiktok           → com.zhiliaoapp.musically
  chrome           → com.google.Chrome
  safari           → com.apple.safari
  vscode           → com.microsoft.VSCode
  terminal         → com.apple.Terminal
  iterm            → com.googlecode.iterm2
  figma            → com.figma.Desktop
  zoom             → us.zoom.xos
  reddit           → org.reddit.reddit
  whatsapp         → net.whatsapp.WhatsApp
  telegram         → ru.keepcoder.Telegram
  notion           → notion.id
  linear           → com.linear.Linear
  github desktop   → com.github.GitHubDesktop"""


# ---------------------------------------------------------------------------
# Few-shot examples
# ---------------------------------------------------------------------------

FEW_SHOT_EXAMPLES = """\
--- EXAMPLE 1: Report writing ---
User intent: I need to finish my quarterly report

Output:
{
  "schema_version": "1.0",
  "session_id": "f47ac10b-58cc-4372-a567-0e02b2c3d479",
  "intent": {
    "raw": "I need to finish my quarterly report",
    "normalised": "i need to finish my quarterly report",
    "confidence": 0.96
  },
  "session": {
    "duration_minutes": 90,
    "hard_stop": false
  },
  "apps": {
    "mode": "block_listed",
    "blocked": [
      {"bundle_id": "com.twitter.twitter", "display_name": "Twitter"},
      {"bundle_id": "com.burbn.instagram", "display_name": "Instagram"},
      {"bundle_id": "com.tinyspeck.slackmacgap", "display_name": "Slack"},
      {"bundle_id": "com.hnc.Discord", "display_name": "Discord"}
    ],
    "allowed": []
  },
  "urls": {
    "rules": [
      {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "instagram.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "reddit.com", "action": "block", "exceptions": [], "reason": "social media distraction"}
    ]
  },
  "notifications": {"mode": "suppress_all"},
  "escape_hatch": {
    "mode": "standard",
    "delay_seconds": 30,
    "require_reason": true,
    "min_reason_chars": 20,
    "exception_scope": "scoped",
    "active_exceptions": []
  }
}

--- EXAMPLE 2: Watching lecture videos ---
User intent: watching lecture videos on distributed systems on YouTube

Output:
{
  "schema_version": "1.0",
  "session_id": "550e8400-e29b-41d4-a716-446655440000",
  "intent": {
    "raw": "watching lecture videos on distributed systems on YouTube",
    "normalised": "watching lecture videos on distributed systems on youtube",
    "confidence": 0.91
  },
  "session": {
    "duration_minutes": 120,
    "hard_stop": false
  },
  "apps": {
    "mode": "block_listed",
    "blocked": [
      {"bundle_id": "com.twitter.twitter", "display_name": "Twitter"},
      {"bundle_id": "com.burbn.instagram", "display_name": "Instagram"},
      {"bundle_id": "com.tinyspeck.slackmacgap", "display_name": "Slack"}
    ],
    "allowed": []
  },
  "urls": {
    "rules": [
      {
        "pattern": "youtube.com",
        "action": "block",
        "exceptions": [
          {"pattern": "youtube.com/watch", "reason": "lecture videos"},
          {"pattern": "youtube.com/playlist", "reason": "lecture playlists"}
        ],
        "reason": "youtube feed is distracting but watch and playlist pages are needed for lectures"
      },
      {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "instagram.com", "action": "block", "exceptions": [], "reason": "social media distraction"}
    ]
  },
  "notifications": {"mode": "allow_calendar"},
  "escape_hatch": {
    "mode": "standard",
    "delay_seconds": 30,
    "require_reason": true,
    "min_reason_chars": 20,
    "exception_scope": "scoped",
    "active_exceptions": []
  }
}

--- EXAMPLE 3: Deep coding work ---
User intent: deep coding work on my side project, no interruptions at all

Output:
{
  "schema_version": "1.0",
  "session_id": "6ba7b810-9dad-11d1-80b4-00c04fd430c8",
  "intent": {
    "raw": "deep coding work on my side project, no interruptions at all",
    "normalised": "deep coding work on my side project, no interruptions at all",
    "confidence": 0.98
  },
  "session": {
    "duration_minutes": 180,
    "hard_stop": false
  },
  "apps": {
    "mode": "allow_listed",
    "blocked": [],
    "allowed": [
      {"bundle_id": "com.microsoft.VSCode", "display_name": "VS Code"},
      {"bundle_id": "com.apple.Terminal", "display_name": "Terminal"},
      {"bundle_id": "com.googlecode.iterm2", "display_name": "iTerm2"},
      {"bundle_id": "com.google.Chrome", "display_name": "Chrome"}
    ]
  },
  "urls": {
    "rules": [
      {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "instagram.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "reddit.com", "action": "block", "exceptions": [], "reason": "social media distraction"},
      {"pattern": "youtube.com", "action": "block", "exceptions": [], "reason": "video distraction"}
    ]
  },
  "notifications": {"mode": "suppress_all"},
  "escape_hatch": {
    "mode": "standard",
    "delay_seconds": 30,
    "require_reason": true,
    "min_reason_chars": 20,
    "exception_scope": "scoped",
    "active_exceptions": []
  }
}"""


# ---------------------------------------------------------------------------
# Prompt builder
# ---------------------------------------------------------------------------

def build_prompt(raw_intent: str) -> str:
    """
    Build the full prompt string to send to qwen3:8b via Ollama.

    The prompt sets system context, provides the bundle ID lookup table,
    three few-shot examples, fixed MVP escape_hatch rules, and the user's
    actual intent at the end.
    """
    system_context = """\
You are an AI assistant that generates focus session policy objects for a macOS \
productivity app called Stira. Stira helps users stay focused by reshaping their \
digital environment to match a declared intent. Given the user's natural language \
intent, you produce a single valid StiraPolicy JSON object that configures which \
apps to block or allow, which URLs to block (with conditional exceptions), the \
session duration, notification posture, and escape hatch settings. Your output \
must be a complete, valid JSON object — no markdown fences, no explanation, just \
the JSON."""

    field_instructions = """\
Field instructions:
- session_id: generate a UUID v4 string (e.g. "550e8400-e29b-41d4-a716-446655440000")
- schema_version: always "1.0"
- intent.raw: the verbatim user input string, unchanged
- intent.normalised: the user input converted to lowercase and trimmed of leading/trailing whitespace
- intent.confidence: a float between 0.0 and 1.0 reflecting how clearly the intent maps to a focus policy \
  (1.0 = crystal clear, 0.5 = ambiguous, 0.0 = incomprehensible)
- escape_hatch.mode: always "standard" for MVP
- escape_hatch.delay_seconds: always 30
- escape_hatch.require_reason: always true
- escape_hatch.min_reason_chars: always 20
- escape_hatch.exception_scope: always "scoped"
- escape_hatch.active_exceptions: always [] (empty array — no pre-granted exceptions)
- apps.mode: use "block_listed" when the user wants to block specific distracting apps; \
  use "allow_listed" when the user wants strict focus (only specific tools allowed)
- urls.rules: block social media and distracting sites implied by the intent; \
  use exceptions for conditional access (e.g. youtube.com/watch allowed when watching lectures)
- session.duration_minutes: infer a reasonable duration from the intent (90 for reports, \
  120 for lectures, 180 for deep work); use 0 if no duration can be inferred
- notifications.mode: use "suppress_all" for deep focus; "allow_calendar" when the user \
  may need meeting reminders; "allow_calls_only" for urgent work; "allow_all" for light focus"""

    prompt = f"""{system_context}

{BUNDLE_ID_TABLE}

{field_instructions}

Below are three examples showing the expected output format and reasoning:

{FEW_SHOT_EXAMPLES}

---
Now generate the StiraPolicy JSON for the following intent. \
Output only the JSON object — nothing else.

User intent: {raw_intent}"""

    return prompt
