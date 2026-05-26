# Stira MVP — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build the Stira MVP — local intent parsing via qwen3:8b/Ollama, macOS enforcement via modified Hermes, Chrome URL enforcement via browser extension, minimal SwiftUI app, and a bundled installer — passing the 10-second test.

**Architecture:** User types intent → SwiftUI app calls local Ollama (qwen3:8b) to produce a StiraPolicy JSON object → Session Manager passes policy to Hermes subprocess (Unix socket) and to Chrome extension (native messaging) → Hermes suppresses/kills focus on blocked apps; extension blocks URLs. All local, no cloud during sessions.

**Tech Stack:** Swift 5.9 + SwiftUI (native app), Python 3.11 + Ollama SDK (intent engine), Python 3.11 (Hermes subprocess), TypeScript + Chrome MV3 (browser extension), JSON Schema draft-07 (policy schema), Unix domain socket with newline-delimited JSON (IPC).

---

## Critical Architectural Decisions (Do Not Relitigate)

These are final per CLAUDE.md — any subagent that questions them is wrong:

1. **Intent Engine:** Ollama + qwen3:8b, localhost:11434. Constrained JSON via Ollama's `format` parameter. Do NOT use Claude API for MVP.
2. **IPC:** Unix domain socket at `~/Library/Application Support/Stira/hermes.sock`. Newline-delimited JSON. NOT XPC (XPC was evaluated and rejected — requires C bindings on Python side).
3. **Policy schema:** Central data structure. Every component either produces or consumes it. Schema is defined once and all components import the same type definitions.
4. **Enforcement is policy-lookup only:** LLM fires once at session start. Hermes never calls the LLM during enforcement. Every block decision is a dictionary lookup against the pre-computed policy.
5. **Hermes is invisible:** No window, no UI, no terminal visible to user. Background subprocess only.
6. **Browser scope:** Chrome only for MVP. Safari is post-MVP.
7. **Escape hatch:** Standard mode only. 30-second delay, 20-character minimum reason, scoped exception only. No global disable.
8. **Installer:** Bundles Ollama + qwen3:8b. Never shows a terminal to the user. Ollama install and model pull happen inside Stira's own UI with a progress bar.
9. **RAM minimum:** 8GB. Enforce at launch.
10. **Memory path:** `~/Library/Application Support/Stira/hermes-memory/`. Nothing leaves the machine.

---

## Repository Layout

```
stira/
├── docs/
│   └── schema/
│       └── stira-policy.schema.json        # Source of truth — Task 1
├── intent-engine/
│   ├── pyproject.toml
│   └── src/
│       ├── stira_policy.py                  # Python types — Task 1
│       ├── intent_engine.py                 # Ollama call — Task 2
│       └── prompt_builder.py                # System prompt — Task 2
├── hermes/                                  # Hermes fork — Task 3
│   └── stira/
│       ├── main.py
│       ├── policy_receiver.py
│       ├── event_emitter.py
│       ├── session_controller.py
│       └── skills/
│           ├── app_suppressor.py
│           ├── focus_killer.py
│           └── app_monitor.py
├── browser-extension/                       # Task 4
│   ├── manifest.json
│   ├── package.json
│   ├── background/
│   │   └── service_worker.ts
│   └── rules/
│       └── rule_builder.ts
├── stira-macos/                             # Task 5
│   ├── Package.swift
│   └── Sources/Stira/
│       ├── App/
│       │   └── StiraApp.swift
│       ├── Models/
│       │   └── StiraPolicy.swift            # Swift types — Task 1
│       ├── PolicyStore/
│       │   └── PolicyStore.swift
│       ├── SessionManager/
│       │   ├── SessionManager.swift
│       │   └── EscapeHatchController.swift
│       ├── HermesSocket/
│       │   └── HermesSocket.swift
│       ├── ExtensionBridge/
│       │   └── ExtensionBridge.swift
│       └── UI/
│           ├── IntentInputView.swift
│           ├── SessionStatusView.swift
│           └── EscapeHatchView.swift
└── scripts/
    └── install-native-messaging.sh          # Task 6
```

---

## Build Order (Enforced by CLAUDE.md)

```
Task 1: Policy Schema            ← STOP for user approval before Task 2
Task 2: Intent Engine (Ollama)   ← STOP for user sign-off before Task 3
Task 3: Hermes Modification      ← STOP for user sign-off before Task 4
Task 4: Browser Extension        ← STOP for user sign-off before Task 5
Task 5: SwiftUI Native App       ← STOP for user sign-off before Task 6
Task 6: Installer + First-Run    ← Final sign-off
```

---

## Task 1: Policy Schema

**Purpose:** Define `stira-policy.schema.json` (source of truth), then derive the Python dataclass and Swift struct from it. Every other component imports from these files — nothing defines StiraPolicy independently.

**Files:**
- Create: `docs/schema/stira-policy.schema.json`
- Create: `intent-engine/src/stira_policy.py`
- Create: `stira-macos/Sources/Stira/Models/StiraPolicy.swift`
- Create: `intent-engine/tests/test_policy_schema.py`

**Context for the schema:** The schema must satisfy Ollama's `format` parameter, which accepts a JSON Schema object. qwen3:8b uses this schema for constrained decoding at the token level — the model cannot generate output that violates the schema. This means:
- All string enum values must be listed explicitly
- Arrays must have `items` defined
- No `$ref` — Ollama's constrained decoding requires a fully-inlined schema (no external references)
- No regex patterns — keep to primitive types, enums, and nested objects
- `required` arrays must be exhaustive on every object — Ollama will not generate optional fields unless you tell it they are optional

**Schema fields required by CLAUDE.md:**

```
StiraPolicy
├── schema_version: "1.0"                    # string, const
├── session_id: uuid                          # string
├── intent
│   ├── raw: string                           # verbatim user input
│   ├── normalised: string                    # lowercased + trimmed
│   └── confidence: number 0.0–1.0            # model self-reports this
├── session
│   ├── duration_minutes: integer ≥ 0         # 0 = indefinite
│   └── hard_stop: boolean
├── apps
│   ├── mode: "block_listed" | "allow_listed"
│   ├── blocked: AppRule[]
│   └── allowed: AppRule[]
├── urls
│   └── rules: UrlRule[]
├── notifications
│   └── mode: "suppress_all"|"allow_all"|"allow_calendar"|"allow_calls_only"
└── escape_hatch
    ├── mode: "soft"|"standard"|"strict"|"nuclear"  # MVP always "standard"
    ├── delay_seconds: integer                       # MVP always 30
    ├── require_reason: boolean                      # MVP always true
    ├── min_reason_chars: integer                    # MVP always 20
    ├── exception_scope: "scoped"|"global"           # MVP always "scoped"
    └── active_exceptions: ScopedException[]

AppRule { bundle_id: string, display_name: string }
UrlRule  { pattern: string, action: "block"|"allow", exceptions: UrlException[], reason: string }
UrlException { pattern: string, reason: string }
ScopedException {
  exception_id: string,
  target_type: "app"|"url",
  target: string,
  granted_at: string,     # ISO 8601
  expires_at: string,     # ISO 8601
  reason: string
}
```

**Important design note:** The JSON Schema handed to Ollama must be self-contained (no `$ref`). Inline all sub-object definitions. The Python dataclass and Swift struct are hand-maintained mirrors of this schema — they are not auto-generated (no code generation tooling needed for MVP).

- [ ] **Step 1: Write the failing schema validation test**

```
intent-engine/tests/test_policy_schema.py
```

```python
import json
import pytest
from pathlib import Path
import jsonschema

SCHEMA_PATH = Path(__file__).parent.parent.parent / "docs" / "schema" / "stira-policy.schema.json"

VALID_POLICY = {
    "schema_version": "1.0",
    "session_id": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
    "intent": {
        "raw": "I need to finish my quarterly report",
        "normalised": "i need to finish my quarterly report",
        "confidence": 0.96
    },
    "session": {"duration_minutes": 90, "hard_stop": False},
    "apps": {
        "mode": "block_listed",
        "blocked": [{"bundle_id": "com.twitter.twitter", "display_name": "Twitter"}],
        "allowed": []
    },
    "urls": {
        "rules": [
            {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media"}
        ]
    },
    "notifications": {"mode": "suppress_all"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 30,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

YOUTUBE_LECTURE_POLICY = {
    "schema_version": "1.0",
    "session_id": "b2c3d4e5-f6a7-8901-bcde-f12345678901",
    "intent": {
        "raw": "Watching lecture videos on distributed systems",
        "normalised": "watching lecture videos on distributed systems",
        "confidence": 0.89
    },
    "session": {"duration_minutes": 120, "hard_stop": False},
    "apps": {
        "mode": "block_listed",
        "blocked": [{"bundle_id": "com.tinyspeck.slackmacgap", "display_name": "Slack"}],
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
                "reason": "youtube feed is distracting but watch/playlist needed for lectures"
            }
        ]
    },
    "notifications": {"mode": "allow_calendar"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 30,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

ALLOW_LISTED_POLICY = {
    "schema_version": "1.0",
    "session_id": "c3d4e5f6-a7b8-9012-cdef-123456789012",
    "intent": {
        "raw": "Deep work: coding on my side project, no interruptions",
        "normalised": "deep work: coding on my side project, no interruptions",
        "confidence": 0.98
    },
    "session": {"duration_minutes": 180, "hard_stop": False},
    "apps": {
        "mode": "allow_listed",
        "blocked": [],
        "allowed": [
            {"bundle_id": "com.microsoft.VSCode", "display_name": "VS Code"},
            {"bundle_id": "com.apple.Terminal", "display_name": "Terminal"}
        ]
    },
    "urls": {
        "rules": [
            {"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "social media"}
        ]
    },
    "notifications": {"mode": "suppress_all"},
    "escape_hatch": {
        "mode": "standard",
        "delay_seconds": 60,
        "require_reason": True,
        "min_reason_chars": 20,
        "exception_scope": "scoped",
        "active_exceptions": []
    }
}

def load_schema():
    with open(SCHEMA_PATH) as f:
        return json.load(f)

def test_schema_file_exists():
    assert SCHEMA_PATH.exists(), f"Schema not found at {SCHEMA_PATH}"

def test_valid_policy_passes():
    schema = load_schema()
    jsonschema.validate(VALID_POLICY, schema)  # should not raise

def test_youtube_lecture_policy_passes():
    schema = load_schema()
    jsonschema.validate(YOUTUBE_LECTURE_POLICY, schema)

def test_allow_listed_policy_passes():
    schema = load_schema()
    jsonschema.validate(ALLOW_LISTED_POLICY, schema)

def test_missing_required_field_fails():
    schema = load_schema()
    bad = {**VALID_POLICY}
    del bad["apps"]
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_app_mode_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "apps": {"mode": "whitelist", "blocked": [], "allowed": []}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_url_action_fails():
    schema = load_schema()
    bad_rule = {"pattern": "twitter.com", "action": "ignore", "exceptions": [], "reason": "x"}
    bad = {**VALID_POLICY, "urls": {"rules": [bad_rule]}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_confidence_out_of_range_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "intent": {**VALID_POLICY["intent"], "confidence": 1.5}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_invalid_escape_hatch_mode_fails():
    schema = load_schema()
    bad = {**VALID_POLICY, "escape_hatch": {**VALID_POLICY["escape_hatch"], "mode": "immediate"}}
    with pytest.raises(jsonschema.ValidationError):
        jsonschema.validate(bad, schema)

def test_scoped_exception_structure():
    schema = load_schema()
    policy_with_exception = {
        **VALID_POLICY,
        "escape_hatch": {
            **VALID_POLICY["escape_hatch"],
            "active_exceptions": [{
                "exception_id": "exc-001",
                "target_type": "app",
                "target": "com.twitter.twitter",
                "granted_at": "2026-05-26T10:00:00Z",
                "expires_at": "2026-05-26T10:30:00Z",
                "reason": "checking a specific notification from my manager"
            }]
        }
    }
    jsonschema.validate(policy_with_exception, schema)
```

- [ ] **Step 2: Run test to verify it fails (schema file does not exist yet)**

```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine
pip install pytest jsonschema
pytest tests/test_policy_schema.py::test_schema_file_exists -v
```
Expected: FAIL — `AssertionError: Schema not found at ...`

- [ ] **Step 3: Write the JSON Schema**

```
docs/schema/stira-policy.schema.json
```

The schema must be self-contained (no `$ref`) so Ollama can use it directly as the `format` parameter. All sub-objects are inline. Write a complete, valid JSON Schema draft-07 object with all fields from the spec above.

- [ ] **Step 4: Run all schema tests**

```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine
pytest tests/test_policy_schema.py -v
```
Expected: 10/10 PASS

- [ ] **Step 5: Write the Python dataclass**

```
intent-engine/src/stira_policy.py
```

Python 3.11 dataclasses (no third-party deps for this file). Must mirror the JSON schema exactly. Include a `from_dict(d: dict) -> StiraPolicy` classmethod and a `to_dict() -> dict` method. Use `@dataclass(frozen=True)` for immutability. Include all nested dataclasses.

- [ ] **Step 6: Write the Swift struct**

```
stira-macos/Sources/Stira/Models/StiraPolicy.swift
```

Swift 5.9 `Codable` structs. Must mirror the JSON schema exactly. Use `enum` for all string enums (with `String` raw values). Use `[String: String]` nowhere — use proper typed nested structs. Include `CodingKeys` only if needed for snake_case ↔ camelCase mapping (keep JSON keys as snake_case to match schema exactly — do not camelCase the Swift JSON keys).

- [ ] **Step 7: Add pyproject.toml for intent-engine**

```
intent-engine/pyproject.toml
```

```toml
[build-system]
requires = ["hatchling"]
build-backend = "hatchling.build"

[project]
name = "stira-intent-engine"
version = "0.1.0"
requires-python = ">=3.11"
dependencies = [
    "jsonschema>=4.21",
    "requests>=2.31",
]

[project.optional-dependencies]
dev = ["pytest>=8.0", "pytest-asyncio>=0.23"]
```

- [ ] **Step 8: Commit**

```bash
git add docs/schema/stira-policy.schema.json intent-engine/ stira-macos/Sources/Stira/Models/StiraPolicy.swift
git commit -m "feat: add StiraPolicy schema with Python and Swift type definitions

JSON Schema source of truth at docs/schema/stira-policy.schema.json.
Python dataclass at intent-engine/src/stira_policy.py.
Swift Codable struct at stira-macos/Sources/Stira/Models/StiraPolicy.swift.
All 10 schema validation tests passing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 2: Intent Engine (Ollama + qwen3:8b)

**Purpose:** Python module that accepts natural language intent text and returns a validated `StiraPolicy` object. Uses Ollama's `format` parameter for constrained JSON decoding — the model cannot produce invalid JSON. Must be tested against 10+ varied user intent strings before anything else touches it.

**Prerequisite:** Task 1 complete and approved.

**Files:**
- Create: `intent-engine/src/intent_engine.py`
- Create: `intent-engine/src/prompt_builder.py`
- Modify: `intent-engine/tests/test_policy_schema.py` → also add intent engine tests

**How Ollama constrained decoding works:**

```python
import requests

response = requests.post("http://localhost:11434/api/generate", json={
    "model": "qwen3:8b",
    "prompt": "<full system + user prompt>",
    "format": <schema_dict>,   # ← This is the full JSON Schema object
    "stream": False
})
policy_dict = json.loads(response.json()["response"])
```

The `format` key accepts the full JSON Schema dict. Ollama compiles it into a grammar and uses constrained token sampling — the output is guaranteed to be valid against the schema. No regex parsing, no markdown fences, no post-processing needed.

**System prompt design:** The prompt must:
1. Explain that the user is a knowledge worker starting a focus session
2. Show the schema structure (so the model knows what fields exist)
3. Instruct the model to infer reasonable defaults for unspecified fields
4. Include the curated bundle ID lookup table for common apps
5. Set `confidence` based on how unambiguous the intent was

**Bundle ID lookup table (hardcoded in prompt_builder.py):**

```python
KNOWN_BUNDLE_IDS = {
    "twitter": "com.twitter.twitter",
    "x": "com.twitter.twitter",
    "instagram": "com.burbn.instagram",
    "slack": "com.tinyspeck.slackmacgap",
    "discord": "com.hnc.Discord",
    "messages": "com.apple.iMessage",
    "mail": "com.apple.mail",
    "youtube": "com.google.YouTube",
    "netflix": "com.netflix.Netflix",
    "tiktok": "com.zhiliaoapp.musically",
    "chrome": "com.google.Chrome",
    "safari": "com.apple.safari",
    "vscode": "com.microsoft.VSCode",
    "terminal": "com.apple.Terminal",
    "iterm": "com.googlecode.iterm2",
    "figma": "com.figma.Desktop",
    "zoom": "us.zoom.xos",
    "reddit": "org.reddit.reddit",
    "whatsapp": "net.whatsapp.WhatsApp",
    "telegram": "ru.keepcoder.Telegram",
    "notion": "notion.id",
    "linear": "com.linear.Linear",
    "github desktop": "com.github.GitHubDesktop",
}
```

- [ ] **Step 1: Write failing intent engine tests**

```
intent-engine/tests/test_intent_engine.py
```

```python
import pytest
from unittest.mock import patch, MagicMock
from src.intent_engine import parse_intent, IntentError
from src.stira_policy import StiraPolicy
import json

MOCK_REPORT_POLICY = {
    "schema_version": "1.0",
    "session_id": "mock-session-id",
    "intent": {"raw": "finish my report", "normalised": "finish my report", "confidence": 0.95},
    "session": {"duration_minutes": 90, "hard_stop": False},
    "apps": {"mode": "block_listed", "blocked": [{"bundle_id": "com.twitter.twitter", "display_name": "Twitter"}], "allowed": []},
    "urls": {"rules": [{"pattern": "twitter.com", "action": "block", "exceptions": [], "reason": "distraction"}]},
    "notifications": {"mode": "suppress_all"},
    "escape_hatch": {"mode": "standard", "delay_seconds": 30, "require_reason": True, "min_reason_chars": 20, "exception_scope": "scoped", "active_exceptions": []}
}

def make_mock_response(policy_dict):
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"response": json.dumps(policy_dict)}
    return mock_resp

@patch("src.intent_engine.requests.post")
def test_returns_stira_policy(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert isinstance(result, StiraPolicy)

@patch("src.intent_engine.requests.post")
def test_raw_intent_preserved(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert result.intent.raw == "finish my report"

@patch("src.intent_engine.requests.post")
def test_confidence_in_range(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    result = parse_intent("finish my report")
    assert 0.0 <= result.intent.confidence <= 1.0

@patch("src.intent_engine.requests.post")
def test_api_failure_raises_intent_error(mock_post):
    mock_post.side_effect = Exception("connection refused")
    with pytest.raises(IntentError) as exc:
        parse_intent("finish my report")
    assert exc.value.code == "api_failure"

@patch("src.intent_engine.requests.post")
def test_invalid_json_raises_intent_error(mock_post):
    mock_resp = MagicMock()
    mock_resp.status_code = 200
    mock_resp.json.return_value = {"response": "not json at all"}
    mock_post.return_value = mock_resp
    with pytest.raises(IntentError) as exc:
        parse_intent("finish my report")
    assert exc.value.code == "parse_failure"

@patch("src.intent_engine.requests.post")
def test_prompt_contains_raw_intent(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("write my dissertation chapter")
    call_args = mock_post.call_args
    payload = call_args[1]["json"] if call_args[1] else call_args[0][1]
    assert "write my dissertation chapter" in payload["prompt"]

@patch("src.intent_engine.requests.post")
def test_format_parameter_is_schema_dict(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args[1]["json"] if call_args[1] else call_args[0][1]
    assert "format" in payload
    assert isinstance(payload["format"], dict)
    assert payload["format"].get("type") == "object"

@patch("src.intent_engine.requests.post")
def test_model_is_qwen3_8b(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args[1]["json"] if call_args[1] else call_args[0][1]
    assert payload["model"] == "qwen3:8b"

@patch("src.intent_engine.requests.post")
def test_stream_is_false(mock_post):
    mock_post.return_value = make_mock_response(MOCK_REPORT_POLICY)
    parse_intent("finish my report")
    call_args = mock_post.call_args
    payload = call_args[1]["json"] if call_args[1] else call_args[0][1]
    assert payload["stream"] is False
```

- [ ] **Step 2: Run to verify tests fail**

```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine
pytest tests/test_intent_engine.py -v
```
Expected: FAIL — `ModuleNotFoundError: No module named 'src.intent_engine'`

- [ ] **Step 3: Implement `prompt_builder.py`**

Module with two public functions:
- `build_prompt(raw_intent: str) -> str` — returns the full prompt string for qwen3:8b
- `load_schema() -> dict` — loads and returns the parsed JSON schema from `docs/schema/stira-policy.schema.json`

The system prompt must explain the task, reference the bundle ID table, and ask for a JSON object matching the schema. Include the three example intents (report writing, lecture videos, deep coding work) as few-shot examples in the prompt.

- [ ] **Step 4: Implement `intent_engine.py`**

```python
from dataclasses import dataclass
from src.stira_policy import StiraPolicy

@dataclass
class IntentError(Exception):
    code: str   # "api_failure" | "parse_failure" | "schema_violation"
    message: str
    raw_response: str | None = None

def parse_intent(raw_text: str, ollama_url: str = "http://localhost:11434") -> StiraPolicy:
    ...
```

Implementation must:
1. Call `build_prompt(raw_text)` to get the prompt
2. Call `load_schema()` to get the schema dict for the `format` parameter
3. POST to `{ollama_url}/api/generate` with `model="qwen3:8b"`, `stream=False`, `format=<schema_dict>`
4. Parse the JSON response
5. Validate against the schema using `jsonschema.validate`
6. Return `StiraPolicy.from_dict(policy_dict)`
7. Wrap all exceptions in `IntentError` with appropriate code

- [ ] **Step 5: Run unit tests**

```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine
pytest tests/test_intent_engine.py -v
```
Expected: 9/9 PASS

- [ ] **Step 6: Manual integration test against real Ollama (skip if Ollama not installed)**

```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine
python -c "
from src.intent_engine import parse_intent
import json

intents = [
    'I need to finish my quarterly report',
    'Watching lecture videos on distributed systems',
    'Deep work: coding on my side project',
    'Studying for my calculus exam',
    'Writing my PhD dissertation chapter on NLP',
    'Job search: need to apply to 5 positions today',
    'Reading papers on transformer architectures',
    'Planning my week and clearing my task list',
    'Debugging a production incident',
    'Reviewing PRs and doing code review',
]
for intent in intents:
    try:
        result = parse_intent(intent)
        print(f'OK  [{result.intent.confidence:.2f}] {intent[:50]}')
        print(f'    apps_mode={result.apps.mode}, url_rules={len(result.urls.rules)}')
    except Exception as e:
        print(f'ERR {intent[:50]}: {e}')
"
```
Expected: All 10 print `OK [confidence] ...` with reasonable policy values.

- [ ] **Step 7: Commit**

```bash
git add intent-engine/
git commit -m "feat: add Ollama/qwen3:8b intent engine with constrained JSON decoding

parse_intent() accepts natural language, calls qwen3:8b via Ollama format
parameter for guaranteed-valid policy JSON. 9/9 unit tests passing.
Manual integration test against 10 varied intents successful.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 3: Hermes Modification

**Purpose:** Fork Hermes Agent and strip it down to exactly three enforcement skills (app suppression, focus kill, app monitor), connected to Stira via Unix domain socket. The modified Hermes receives a `HermesTaskSpec` (derived from `StiraPolicy`), enforces it silently, and streams `HermesEvent` objects back.

**Prerequisite:** Task 2 complete and approved.

**Files:**
- Create: `hermes/stira/main.py` — subprocess entry point replacing Hermes chat
- Create: `hermes/stira/policy_receiver.py` — Unix socket server (reads incoming JSON)
- Create: `hermes/stira/event_emitter.py` — Unix socket client (writes outgoing JSON)
- Create: `hermes/stira/session_controller.py` — translates policy → skill calls
- Create: `hermes/stira/skills/app_suppressor.py` — blocks app from foregrounding
- Create: `hermes/stira/skills/focus_killer.py` — kills focus if blocked app comes to front
- Create: `hermes/stira/skills/app_monitor.py` — monitors and logs app opens
- Create: `hermes/tests/test_session_controller.py`
- Create: `hermes/tests/test_socket_protocol.py`

**Socket protocol (from CLAUDE.md):**

```
Stira → Hermes (start):
{"type": "start_session", "policy": <HermesTaskSpec as JSON>}

Hermes → Stira (event):
{"type": "app_blocked", "bundle_id": "com.twitter.twitter", "timestamp": "2026-05-26T10:00:00Z", "session_id": "..."}
{"type": "focus_killed", "bundle_id": "com.twitter.twitter", "timestamp": "...", "session_id": "..."}
{"type": "app_opened", "bundle_id": "com.apple.safari", "timestamp": "...", "session_id": "..."}
{"type": "session_started", "session_id": "...", "timestamp": "..."}
{"type": "session_ended", "session_id": "...", "timestamp": "..."}
{"type": "error", "message": "...", "session_id": "...", "timestamp": "..."}

Stira → Hermes (stop):
{"type": "stop_session", "session_id": "..."}
```

**HermesTaskSpec** (derived from StiraPolicy by the Swift Session Manager before sending):

```json
{
  "spec_version": "1.0",
  "session_id": "...",
  "blocked_bundle_ids": ["com.twitter.twitter", "com.apple.iMessage"],
  "allowed_bundle_ids": [],
  "enforcement_mode": "block_listed",
  "session_duration_seconds": 5400,
  "audit_level": "normal"
}
```

**macOS enforcement via Accessibility APIs:**

For MVP, app suppression uses these mechanisms in order of preference:
1. `NSWorkspace.shared.terminateApplication(_:)` — graceful termination if app is in blocked list and comes to front
2. `AXUIElementCreateApplication(pid)` + `kAXWindowsAttribute` → set window to minimized — less aggressive
3. For focus kill: bring another window to front immediately after detecting focus shift

The `app_monitor` skill uses `NSWorkspace.shared.notificationCenter` to observe `NSWorkspace.didActivateApplicationNotification` and `NSWorkspace.didLaunchApplicationNotification`.

All three skills must be callable from Python via `subprocess` calling a Swift helper binary, OR via `pyobjc` if available. Use `pyobjc` if installed; fall back to calling a Swift CLI helper.

- [ ] **Step 1: Set up Hermes directory and clone**

```bash
mkdir -p /Users/ronith/Documents/Projects/Stira/hermes
cd /Users/ronith/Documents/Projects/Stira/hermes
# Check if Hermes is already there; if not, document where to get it
# Hermes Agent: https://github.com/NousResearch/Hermes (MIT license)
# For now, create the stira/ overlay directory and tests
mkdir -p stira/skills tests
touch stira/__init__.py stira/skills/__init__.py
```

- [ ] **Step 2: Write failing socket protocol tests**

```
hermes/tests/test_socket_protocol.py
```

Tests must verify:
- `policy_receiver` correctly deserialises an incoming `start_session` message
- `policy_receiver` correctly deserialises a `stop_session` message
- `event_emitter` correctly serialises each event type to valid JSON
- Each emitted event has all required fields (`type`, `session_id`, `timestamp`)
- Unknown message types are handled gracefully (logged, not crashed)

- [ ] **Step 3: Write failing session controller tests**

```
hermes/tests/test_session_controller.py
```

Tests must verify:
- `SessionController.start(task_spec)` calls all three skills
- `SessionController.stop()` stops all three skills
- `SessionController` is initialised with a valid `HermesTaskSpec`
- `SessionController` refuses to start if `spec_version` is not `"1.0"`

- [ ] **Step 4: Implement `policy_receiver.py`**

Unix domain socket server. Listens at `~/Library/Application Support/Stira/hermes.sock`. Reads newline-delimited JSON messages. Dispatches to callback functions:
- `on_start_session(task_spec: dict)` — passed to session controller
- `on_stop_session(session_id: str)` — stops enforcement
- `on_unknown(message: dict)` — logs and ignores

- [ ] **Step 5: Implement `event_emitter.py`**

Connects back to the same socket (bidirectional). Writes newline-delimited JSON events. Public methods:
- `emit_session_started(session_id: str)`
- `emit_app_blocked(session_id: str, bundle_id: str)`
- `emit_focus_killed(session_id: str, bundle_id: str)`
- `emit_app_opened(session_id: str, bundle_id: str)`
- `emit_session_ended(session_id: str)`
- `emit_error(session_id: str, message: str)`

Each emits a dict with `type`, `session_id`, `timestamp` (ISO 8601 UTC), and type-specific fields.

- [ ] **Step 6: Implement the three enforcement skills**

`app_suppressor.py` — starts watching for blocked apps (via NSWorkspace notification); when a blocked app activates, calls `focus_killer`
`focus_killer.py` — given a PID, switches focus to the Stira app or Finder immediately
`app_monitor.py` — subscribes to `didActivateApplicationNotification` and `didLaunchApplicationNotification`; calls `event_emitter.emit_app_opened()` for every app open

- [ ] **Step 7: Implement `session_controller.py`**

Translates `HermesTaskSpec` → initialises the three skills → starts them. On stop: gracefully shuts down skills, emits `session_ended`.

- [ ] **Step 8: Implement `main.py`**

Entry point. Creates socket server, emitter, session controller. Runs the socket server event loop. Logs to `~/Library/Application Support/Stira/hermes.log`. Exits cleanly on SIGTERM.

```bash
python -m stira.main --socket-path "$HOME/Library/Application Support/Stira/hermes.sock"
```

- [ ] **Step 9: Run all tests**

```bash
cd /Users/ronith/Documents/Projects/Stira/hermes
pytest tests/ -v
```
Expected: All PASS

- [ ] **Step 10: Commit**

```bash
git add hermes/
git commit -m "feat: add modified Hermes with three hardwired enforcement skills

Unix socket server receives HermesTaskSpec, runs app_suppressor/focus_killer/
app_monitor skills, streams HermesEvent objects back. Hermes runs as invisible
background subprocess. All tests passing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 4: Browser Extension

**Purpose:** Chrome MV3 extension that receives the URL-rule portion of `StiraPolicy` via native messaging and applies them using `declarativeNetRequest`. Supports path-level exceptions (e.g., youtube.com blocked but youtube.com/watch allowed).

**Prerequisite:** Task 3 complete and approved.

**Files:**
- Create: `browser-extension/manifest.json`
- Create: `browser-extension/package.json`
- Create: `browser-extension/tsconfig.json`
- Create: `browser-extension/background/service_worker.ts`
- Create: `browser-extension/rules/rule_builder.ts`
- Create: `browser-extension/tests/rule_builder.test.ts`
- Create: `scripts/install-native-messaging.sh`

**Native messaging protocol:**

The native messaging host is a Swift binary bundled with the macOS app. The extension sends:
```json
{"type": "get_policy", "session_token": "..."}
```
And receives:
```json
{
  "type": "policy",
  "session_token": "...",
  "rules": [
    {"pattern": "twitter.com", "action": "block", "exceptions": []},
    {"pattern": "youtube.com", "action": "block", "exceptions": [
      {"pattern": "youtube.com/watch"},
      {"pattern": "youtube.com/playlist"}
    ]}
  ]
}
```

**declarativeNetRequest rule design:**

Each blocked domain gets a `declarativeNetRequest` rule with `action.type = "block"`. Each exception (allowed sub-path) gets a higher-priority `allow` rule targeting the specific URL pattern. Priority: allow rules at 2, block rules at 1 — so the allow always wins.

```typescript
// youtube.com blocked, youtube.com/watch allowed:
// Rule 1: priority=1, action=block, urlFilter="youtube.com"
// Rule 2: priority=2, action=allow, urlFilter="youtube.com/watch"
```

- [ ] **Step 1: Write failing rule_builder tests**

```
browser-extension/tests/rule_builder.test.ts
```

Tests must verify:
- Single blocked domain produces one block rule
- Blocked domain with one exception produces block rule + allow rule
- Allow rule has higher priority than block rule
- Rule IDs are unique positive integers
- Empty rules array produces no declarativeNetRequest rules
- `youtube.com/watch` exception pattern maps to correct URL filter

- [ ] **Step 2: Run tests to verify failure**

```bash
cd /Users/ronith/Documents/Projects/Stira/browser-extension
npm install && npx jest
```
Expected: FAIL — `Cannot find module './rule_builder'`

- [ ] **Step 3: Implement `rule_builder.ts`**

```typescript
interface ExtensionUrlRule {
  pattern: string;
  action: "block" | "allow";
  exceptions: Array<{ pattern: string }>;
}

interface DNRRule {
  id: number;
  priority: number;
  action: { type: "block" | "allow" };
  condition: { urlFilter: string; resourceTypes: string[] };
}

export function buildDNRRules(urlRules: ExtensionUrlRule[]): DNRRule[] { ... }
```

- [ ] **Step 4: Run tests to verify pass**

```bash
npx jest
```
Expected: All PASS

- [ ] **Step 5: Implement `service_worker.ts`**

On startup: send `get_policy` to native messaging host, receive `policy`, call `buildDNRRules()`, call `chrome.declarativeNetRequest.updateDynamicRules()`.

On native message received with type `policy_update`: re-apply rules.

On native message received with type `session_ended`: clear all dynamic rules.

Handle native messaging host disconnect gracefully (clear rules, log error).

- [ ] **Step 6: Write `manifest.json`**

MV3 manifest. Permissions: `declarativeNetRequest`, `declarativeNetRequestWithHostAccess`, `nativeMessaging`. Host permissions: `<all_urls>`. Background: service worker.

Native messaging host name: `com.stira.extensionbridge`.

- [ ] **Step 7: Write `install-native-messaging.sh`**

Installs the native messaging host manifest at:
- Chrome: `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.stira.extensionbridge.json`

The manifest JSON:
```json
{
  "name": "com.stira.extensionbridge",
  "description": "Stira browser extension bridge",
  "path": "/Applications/Stira.app/Contents/MacOS/StiraExtensionBridge",
  "type": "stdio",
  "allowed_origins": ["chrome-extension://<EXTENSION_ID>/"]
}
```

The script substitutes the actual extension ID from a build artifact or prompts the user.

- [ ] **Step 8: Commit**

```bash
git add browser-extension/ scripts/
git commit -m "feat: add Chrome MV3 browser extension with declarativeNetRequest enforcement

Receives URL policy via native messaging, builds block/allow rules with
path-level exception support (youtube.com blocked, youtube.com/watch allowed).
All rule_builder tests passing.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 5: SwiftUI Native App

**Purpose:** The macOS app. One intent input field, session status display, Standard-mode escape hatch UX. Orchestrates the full session: calls Ollama intent engine, starts Hermes subprocess via Unix socket, pushes policy to browser extension via native messaging host. Minimal — no settings screen, no history view.

**Prerequisite:** Task 4 complete and approved.

**Files:**
- Create: `stira-macos/Package.swift` (Swift Package Manager)
- Create: `stira-macos/Sources/Stira/App/StiraApp.swift`
- Create: `stira-macos/Sources/Stira/PolicyStore/PolicyStore.swift`
- Create: `stira-macos/Sources/Stira/SessionManager/SessionManager.swift`
- Create: `stira-macos/Sources/Stira/SessionManager/EscapeHatchController.swift`
- Create: `stira-macos/Sources/Stira/HermesSocket/HermesSocket.swift`
- Create: `stira-macos/Sources/Stira/ExtensionBridge/ExtensionBridge.swift`
- Create: `stira-macos/Sources/Stira/UI/IntentInputView.swift`
- Create: `stira-macos/Sources/Stira/UI/SessionStatusView.swift`
- Create: `stira-macos/Sources/Stira/UI/EscapeHatchView.swift`

**Session flow:**

```
User types intent → taps "Start Session"
→ SessionManager.startSession(rawIntent: String)
  → Calls Ollama HTTP endpoint (localhost:11434) — same call as intent engine
  → Validates response as StiraPolicy
  → PolicyStore.setActivePolicy(policy)
  → HermesSocket.startSession(taskSpec) via Unix socket
  → ExtensionBridge.pushPolicy(policy)
  → UI transitions to SessionStatusView

During session:
  → HermesSocket receives events → SessionManager.handleHermesEvent()
  → UI updates session status

Escape hatch request:
  → User taps "I need a break"
  → EscapeHatchController.beginEscapeHatch(target, reason)
  → 30-second countdown displayed (immovable — cannot be dismissed)
  → After countdown: reason field (20 char minimum) shown
  → User submits reason
  → ScopedException added to PolicyStore.activePolicy.escape_hatch.active_exceptions
  → HermesSocket and ExtensionBridge notified of scoped exception

Session end:
  → SessionManager.endSession()
  → HermesSocket.stopSession()
  → ExtensionBridge.clearPolicy()
  → Audit log written to disk
  → UI returns to IntentInputView
```

**RAM check at launch:**

```swift
// In StiraApp.swift, before showing main UI:
let physicalMemoryGB = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
if physicalMemoryGB < 8.0 {
    // Show error: "Stira requires 8GB RAM minimum."
    // Exit app
}
```

**HermesSocket IPC:**

Unix domain socket at `~/Library/Application Support/Stira/hermes.sock`. Reads newline-delimited JSON (one message per line). Must handle:
- Socket not yet available (Hermes not running) → retry with 500ms interval, max 10 retries
- Socket disconnect mid-session → emit error to SessionManager, show user-visible error

**ExtensionBridge:**

Implements the native messaging host protocol (stdio-based, as spawned by Chrome). Is a separate Swift binary (`StiraExtensionBridge`) in the app bundle. Reads from stdin, writes to stdout, exactly as Chrome's native messaging spec requires.

When the main Stira app has an active policy, it writes the policy to a shared file at `~/Library/Application Support/Stira/active-policy.json`. The ExtensionBridge binary reads this file when the extension queries it.

- [ ] **Step 1: Set up Swift Package Manager project**

```
stira-macos/Package.swift
```

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Stira",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Stira",
            path: "Sources/Stira",
            resources: []
        ),
        .executableTarget(
            name: "StiraExtensionBridge",
            path: "Sources/StiraExtensionBridge"
        ),
    ]
)
```

- [ ] **Step 2: Implement `StiraPolicy.swift`** (already done in Task 1 — verify it is correct and complete)

- [ ] **Step 3: Implement `PolicyStore.swift`**

`@MainActor` `ObservableObject`. Holds `activePolicy: StiraPolicy?`. Provides `setActivePolicy(_:)`, `clearPolicy()`, `applyException(_: ScopedException)`. Writes the active policy to `~/Library/Application Support/Stira/active-policy.json` on every mutation.

- [ ] **Step 4: Implement `HermesSocket.swift`**

Async class. Manages connection to Hermes Unix socket. Public methods:
- `func startSession(_ taskSpec: HermesTaskSpec) async throws` — sends `start_session` message
- `func stopSession(sessionId: String) async throws` — sends `stop_session` message
- `var events: AsyncStream<HermesEvent>` — streams incoming events

Derives `HermesTaskSpec` from `StiraPolicy` (translates app mode, blocked IDs, duration).

- [ ] **Step 5: Implement `EscapeHatchController.swift`**

`@MainActor` `ObservableObject`. State machine: `idle → countdown → reason_entry → granted`. The countdown is 30 seconds (from `policy.escape_hatch.delay_seconds`). The countdown cannot be cancelled — `cancelCountdown()` is a no-op. After countdown, shows reason entry. Validates reason ≥ 20 characters (from `policy.escape_hatch.min_reason_chars`). On grant, produces `ScopedException` with `expires_at = now + session_duration_remaining / 4` (capped at 30 minutes).

- [ ] **Step 6: Implement `SessionManager.swift`**

`@MainActor` `ObservableObject`. State: `SessionState` enum `idle | starting | active | escape_hatch | ending`. Orchestrates: intent call → PolicyStore → HermesSocket → ExtensionBridge. Handles Hermes events, updates audit log. On session end, writes JSONL audit log to `~/Library/Application Support/Stira/sessions/{session_id}/audit.jsonl`.

- [ ] **Step 7: Implement `IntentInputView.swift`**

Single text field (multiline, large font), "Start Session" button. Button disabled while `sessionManager.state == .starting`. Shows loading spinner during intent parsing. Error message if intent fails.

- [ ] **Step 8: Implement `SessionStatusView.swift`**

Shows: elapsed time, session mode (app enforcement mode + number of blocked apps), number of URLs blocked. "End Session" button. "I need a break" button that triggers escape hatch.

- [ ] **Step 9: Implement `EscapeHatchView.swift`**

Shown when escape hatch is triggered. Countdown circle (immovable, cannot dismiss). After countdown: neutral-language prompt ("You asked to stay in [intent mode] — open [app] for how long?"). Text field for reason (shows character count, minimum 20). Submit button disabled until reason is valid.

- [ ] **Step 10: Implement `StiraApp.swift`**

`@main App`. Adds RAM check at startup. Uses `@StateObject` for SessionManager. Switches between `IntentInputView` and `SessionStatusView` based on session state. `EscapeHatchView` is a sheet.

- [ ] **Step 11: Build and verify it compiles**

```bash
cd /Users/ronith/Documents/Projects/Stira/stira-macos
swift build
```
Expected: Build succeeded, 0 errors.

- [ ] **Step 12: Commit**

```bash
git add stira-macos/
git commit -m "feat: add SwiftUI native app with session management and escape hatch

Intent input → Ollama call → Hermes socket → Extension bridge. Standard escape
hatch: 30s immovable countdown, 20-char minimum reason, scoped exception.
RAM check at launch. Compiles cleanly.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Task 6: Installer + First-Run Flow

**Purpose:** The installer bundles Ollama and handles qwen3:8b download inside Stira's own UI — the user never sees a terminal. First-run flow: RAM check → Ollama install → model pull with progress bar → Accessibility permission onboarding. This is the first thing every user sees; polish it disproportionately.

**Prerequisite:** Task 5 complete and approved.

**Files:**
- Create: `stira-macos/Sources/Stira/Onboarding/OnboardingCoordinator.swift`
- Create: `stira-macos/Sources/Stira/Onboarding/OllamaInstaller.swift`
- Create: `stira-macos/Sources/Stira/Onboarding/ModelDownloadView.swift`
- Create: `stira-macos/Sources/Stira/Onboarding/PermissionOnboardingView.swift`
- Create: `stira-macos/Sources/Stira/Onboarding/OnboardingView.swift`
- Modify: `stira-macos/Sources/Stira/App/StiraApp.swift` — add onboarding gate

**Onboarding flow:**

```
Launch
  ↓
RAM check (< 8GB → show error, exit)
  ↓
Is Ollama installed? (check `which ollama` or HTTP ping to localhost:11434)
  NO → Install Ollama silently (download pkg, run installer via AppleScript or AuthorizationRef)
  YES → Skip
  ↓
Is qwen3:8b pulled? (GET localhost:11434/api/tags, check for qwen3:8b)
  NO → Show ModelDownloadView: "Downloading AI model (5GB, one-time)" + progress bar
       Call localhost:11434/api/pull with stream=true, parse progress events
  YES → Skip
  ↓
Does Stira have Accessibility permission? (AXIsProcessTrusted())
  NO → Show PermissionOnboardingView:
        - Brief value demo: "Stira enforces your focus by suppressing distracting apps"
        - "Open System Settings" button → deep link to Accessibility pane
        - Poll AXIsProcessTrusted() every 2 seconds, auto-advance when granted
  YES → Skip
  ↓
Onboarding complete → show IntentInputView
```

**Ollama install approach:**

1. Check if Ollama binary exists at `/usr/local/bin/ollama` or via `which ollama`
2. Check if Ollama HTTP API is responsive at `localhost:11434/api/version`
3. If neither: download the Ollama macOS installer from a bundled URL (or embed the binary in the app bundle)
4. Run the installer silently. Use `Process` to run the installer pkg via `installer -pkg /path/to/ollama.pkg -target /`

**Model download with real progress:**

Ollama's pull API returns a stream of JSON objects:
```
{"status": "pulling manifest"}
{"status": "pulling abc123", "digest": "sha256:...", "total": 5368709120, "completed": 102400}
...
{"status": "success"}
```
Parse these and show a `ProgressView` with percentage complete.

**Deep link to Accessibility:**

```swift
URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility")
```

- [ ] **Step 1: Implement `OllamaInstaller.swift`**

- [ ] **Step 2: Implement `ModelDownloadView.swift`**

Progress bar reading real Ollama pull stream events.

- [ ] **Step 3: Implement `PermissionOnboardingView.swift`**

Value demo + deep link button + polling check.

- [ ] **Step 4: Implement `OnboardingCoordinator.swift`**

State machine: checks each condition, advances when satisfied.

- [ ] **Step 5: Implement `OnboardingView.swift`**

Container view routing to each onboarding step view.

- [ ] **Step 6: Modify `StiraApp.swift`**

Gate the main UI behind `onboardingCoordinator.isComplete`.

- [ ] **Step 7: Build and verify**

```bash
cd /Users/ronith/Documents/Projects/Stira/stira-macos
swift build
```
Expected: Build succeeded.

- [ ] **Step 8: Commit**

```bash
git add stira-macos/Sources/Stira/Onboarding/
git commit -m "feat: add installer and first-run onboarding flow

Ollama detection/install, qwen3:8b pull with real progress bar, Accessibility
permission deep-link with auto-advance. No terminal ever shown to user.

Co-Authored-By: Claude Sonnet 4.6 <noreply@anthropic.com>"
```

---

## Acceptance Criterion

The 10-second test:
1. Fresh launch (Ollama + model already installed)
2. User types intent: "Deep work — coding on my side project"
3. Taps "Start Session"
4. Within 10 seconds: Twitter is blocked from foregrounding, `twitter.com` is blocked in Chrome
5. One permission ask (Accessibility) has been shown at first launch and is not re-asked

If this sequence requires any configuration, the MVP has failed.
