# Stira MVP — Session Handoff

**Date:** 2026-05-26  
**Branch:** master  
**Last commit:** `746f7bf` feat: add Ollama/qwen3:8b intent engine with constrained JSON decoding

---

## What Stira Is

Local-first macOS focus app. User types intent in plain language → local LLM produces a JSON policy → macOS enforcement (Hermes subprocess) blocks distracting apps → Chrome extension blocks URLs. No cloud during sessions. Full context in [CLAUDE.md](CLAUDE.md).

---

## Current Build State

| Task | Component | Status |
|------|-----------|--------|
| 1 | Policy Schema (JSON Schema + Python dataclass + Swift struct) | ✅ Done |
| 2 | Intent Engine (Ollama + qwen3:8b constrained decoding) | ✅ Done |
| 3 | Hermes Modification (Unix socket + 3 enforcement skills) | ⏳ Next — awaiting sign-off |
| 4 | Browser Extension (Chrome MV3, declarativeNetRequest) | ⬜ Pending |
| 5 | SwiftUI Native App (intent input, session manager, escape hatch) | ⬜ Pending |
| 6 | Installer + First-Run Flow (Ollama bundle, model pull, permissions) | ⬜ Pending |

**Tests:** 20/20 passing  
```bash
cd /Users/ronith/Documents/Projects/Stira/intent-engine && python3 -m pytest tests/ -v
```

---

## Files That Exist

```
stira/
├── CLAUDE.md                                        ← source of truth for ALL decisions
├── HANDOFF.md                                       ← this file
├── .gitignore
├── docs/
│   ├── schema/
│   │   └── stira-policy.schema.json                 ← Task 1 ✅ (Ollama format parameter)
│   └── superpowers/plans/
│       ├── 2026-05-25-stira-architecture.md         ← high-level architecture spec
│       └── 2026-05-26-stira-mvp-implementation.md  ← full task-by-task implementation plan
├── intent-engine/
│   ├── pyproject.toml
│   ├── src/
│   │   ├── __init__.py
│   │   ├── stira_policy.py                          ← Task 1 ✅ frozen Python dataclasses
│   │   ├── intent_engine.py                         ← Task 2 ✅ parse_intent() + IntentError
│   │   └── prompt_builder.py                        ← Task 2 ✅ build_prompt() + load_schema()
│   └── tests/
│       ├── __init__.py
│       ├── test_policy_schema.py                    ← 10 tests ✅
│       └── test_intent_engine.py                    ← 10 tests ✅
└── stira-macos/
    └── Sources/Stira/Models/
        └── StiraPolicy.swift                        ← Task 1 ✅ Codable/Equatable structs
```

---

## Architecture Decisions (Final — Do Not Relitigate)

These are locked per CLAUDE.md. Any agent questioning them is wrong:

| Decision | Choice | Rejected |
|----------|--------|---------|
| Intent Engine (MVP) | Ollama + qwen3:8b at localhost:11434 | Claude API (post-MVP only) |
| Constrained decoding | Ollama `format` parameter (schema dict) | Prompt-only JSON instruction |
| IPC (Swift ↔ Hermes) | Unix domain socket, newline-delimited JSON | XPC (requires C bindings on Python side) |
| Native app | Swift + SwiftUI, macOS 14 minimum | Electron, Tauri |
| Browser scope | Chrome only (MVP) | Safari (post-MVP) |
| Escape hatch (MVP) | Standard mode only: 30s delay, 20-char reason, scoped | Soft/Strict/Nuclear |
| RAM minimum | 8GB | — |
| Memory path | `~/Library/Application Support/Stira/hermes-memory/` | — |
| Socket path | `~/Library/Application Support/Stira/hermes.sock` | — |
| Hermes version | Pin to specific commit hash | Float on main |

---

## What Task 1 Built

### `docs/schema/stira-policy.schema.json`
Self-contained JSON Schema draft-07 (no `$ref`) used as Ollama's `format` parameter. Top-level fields: `schema_version`, `session_id`, `intent`, `session`, `apps`, `urls`, `notifications`, `escape_hatch`. `additionalProperties: false` everywhere.

### `intent-engine/src/stira_policy.py`
Frozen Python dataclasses (`@dataclass(frozen=True)`) mirroring the schema. All have `from_dict(d: dict) -> T` and `to_dict() -> dict`. Stdlib only. Classes: `StiraPolicy`, `IntentInfo`, `SessionInfo`, `AppsConfig`, `UrlsConfig`, `NotificationsConfig`, `EscapeHatchConfig`, `AppRule`, `UrlRule`, `UrlException`, `ScopedException`.

### `stira-macos/Sources/Stira/Models/StiraPolicy.swift`
Swift 5.9 `Codable` + `Equatable` structs. All string enums have `String` raw values matching schema exactly (e.g., `case blockListed = "block_listed"`). `CodingKeys` for snake_case↔camelCase. `StiraPolicy.example` static property.

---

## What Task 2 Built

### `intent-engine/src/intent_engine.py`
```python
def parse_intent(raw_text: str, ollama_url: str = "http://localhost:11434") -> StiraPolicy
```
- POSTs to `{ollama_url}/api/generate` with `model="qwen3:8b"`, `stream=False`, `format=<schema_dict>`, 30s timeout
- Returns `StiraPolicy.from_dict(parsed_response)`
- Raises `IntentError(code="api_failure"|"parse_failure"|"schema_violation", message=..., raw_response=...)`

### `intent-engine/src/prompt_builder.py`
```python
def build_prompt(raw_intent: str) -> str
def load_schema() -> dict
```
- Prompt includes: system context, 22-entry bundle ID table, 3 few-shot examples (report/lecture/coding), MVP escape_hatch field instructions (mode=standard, delay=30, min_reason=20), then `User intent: {raw_intent}`
- `load_schema()` reads `docs/schema/stira-policy.schema.json` and returns parsed dict for `format` param

---

## Task 3: What To Build Next (Hermes Modification)

**Read the full task spec first:** [docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md](docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md) — search for `## Task 3`.

**Summary:** Modify the Hermes Agent (Python, MIT license) to run as an invisible background subprocess with exactly three hardwired enforcement skills. Strip the chat interface. Wire a Unix domain socket server for input and output.

**Socket protocol (from CLAUDE.md):**
```
Stira → Hermes:  {"type": "start_session", "policy": <HermesTaskSpec JSON>}
Hermes → Stira:  {"type": "app_blocked", "bundle_id": "...", "timestamp": "...", "session_id": "..."}
Hermes → Stira:  {"type": "focus_killed", "bundle_id": "...", "timestamp": "...", "session_id": "..."}
Hermes → Stira:  {"type": "app_opened", "bundle_id": "...", "timestamp": "...", "session_id": "..."}
Stira → Hermes:  {"type": "stop_session", "session_id": "..."}
```

**HermesTaskSpec** (what Stira sends, derived from StiraPolicy):
```json
{
  "spec_version": "1.0",
  "session_id": "uuid",
  "blocked_bundle_ids": ["com.twitter.twitter"],
  "allowed_bundle_ids": [],
  "enforcement_mode": "block_listed",
  "session_duration_seconds": 5400,
  "audit_level": "normal"
}
```

**Three enforcement skills (macOS Accessibility APIs via pyobjc):**
1. `app_suppressor.py` — watches for blocked apps activating via `NSWorkspace.didActivateApplicationNotification`
2. `focus_killer.py` — given a PID, immediately switches focus away (to Stira app or Finder)
3. `app_monitor.py` — logs every app open/activate during session via NSWorkspace notifications

**Files to create:**
```
hermes/stira/main.py             ← entry point, replaces Hermes chat
hermes/stira/policy_receiver.py  ← Unix socket server
hermes/stira/event_emitter.py    ← Unix socket writer
hermes/stira/session_controller.py
hermes/stira/skills/app_suppressor.py
hermes/stira/skills/focus_killer.py
hermes/stira/skills/app_monitor.py
hermes/tests/test_session_controller.py
hermes/tests/test_socket_protocol.py
```

**STOP after Task 3 for user sign-off before proceeding to Task 4.**

---

## Workflow Protocol

The CLAUDE.md requires sign-off between each component:
- Complete a task fully (TDD + 2-stage review: spec compliance then code quality)
- Present results to user
- Wait for sign-off before starting next task
- If user says "proceed" or "approved", start the next task

Use subagent-driven development (`superpowers:subagent-driven-development` skill). Fresh subagent per task. Two-stage review after each implementer run.

---

## How To Verify Current State

```bash
# Check all tests pass
cd /Users/ronith/Documents/Projects/Stira/intent-engine
python3 -m pytest tests/ -v
# Expected: 20 passed

# Check git log
git log --oneline
# Expected 4 commits:
# 746f7bf feat: add Ollama/qwen3:8b intent engine...
# 13d31ea fix: remove unused datetime import
# caf5b84 feat: add StiraPolicy schema...
# df33af8 chore: initial project setup
```

---

## Key Files To Read Before Starting

1. [CLAUDE.md](CLAUDE.md) — all product and architecture decisions (authoritative)
2. [docs/schema/stira-policy.schema.json](docs/schema/stira-policy.schema.json) — the central data structure
3. [docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md](docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md) — full implementation plan with code for all 6 tasks
