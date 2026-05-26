# Stira MVP — Session Handoff

**Date:** 2026-05-27  
**Branch:** master  
**Last commit:** `58a34dd` fix: resolve runtime bugs in Swift app — SIGPIPE, fd leaks, event stream lifecycle

---

## Start Here (Paste Into New Session)

```
Read HANDOFF.md, then CLAUDE.md. We're building the Stira MVP using
superpowers:subagent-driven-development. Tasks 1-5 are done (43/43 tests
passing). Task 6 (Installer + First-Run Flow) is next — awaiting sign-off.
Full task spec is in docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md
under ## Task 6.
```

---

## Task List

- [x] **Task 1** — Policy Schema: `stira-policy.schema.json`, `stira_policy.py`, `StiraPolicy.swift` — 10/10 tests
- [x] **Task 2** — Intent Engine: `intent_engine.py`, `prompt_builder.py` — 10/10 tests (20/20 total)
- [x] **Task 3** — Hermes Modification: Unix socket server/emitter + 3 enforcement skills — 16/16 tests (36/36 total)
- [x] **Task 4** — Browser Extension: Chrome MV3, `declarativeNetRequest`, path-level exceptions — 7/7 tests (43/43 total)
- [x] **Task 5** — SwiftUI Native App: intent input, session manager, escape hatch UX — `swift build` ✅
- [ ] **Task 6** — Installer + First-Run: Ollama bundle, qwen3:8b pull progress bar, Accessibility onboarding ← **NEXT (awaiting sign-off)**

**Total tests passing:** 43/43 (Swift app verified by clean `swift build`)  
**Acceptance criterion:** 10-second test (intent → visible enforcement, one permission ask)

---

## What Stira Is

Local-first macOS focus app. User types intent in plain language → local LLM produces a JSON policy → macOS enforcement (Hermes subprocess) blocks distracting apps → Chrome extension blocks URLs. No cloud during sessions. Full context in [CLAUDE.md](CLAUDE.md).

---

## Current Build State

| Task | Component | Status |
|------|-----------|--------|
| 1 | Policy Schema (JSON Schema + Python dataclass + Swift struct) | ✅ Done |
| 2 | Intent Engine (Ollama + qwen3:8b constrained decoding) | ✅ Done |
| 3 | Hermes Modification (Unix socket + 3 enforcement skills) | ✅ Done |
| 4 | Browser Extension (Chrome MV3, declarativeNetRequest) | ✅ Done |
| 5 | SwiftUI Native App (intent input, session manager, escape hatch) | ✅ Done |
| 6 | Installer + First-Run Flow (Ollama bundle, model pull, permissions) | ⏳ Next — awaiting sign-off |

**Tests:** 43/43 passing  
```bash
# Intent engine (20 tests)
cd /Users/ronith/Documents/Projects/Stira/intent-engine && python3 -m pytest tests/ -v
# Hermes (16 tests)
cd /Users/ronith/Documents/Projects/Stira/hermes && python3 -m pytest tests/ -v
# Browser extension (7 tests)
cd /Users/ronith/Documents/Projects/Stira/browser-extension && npx jest
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

## What Task 3 Built

### `hermes/stira/main.py`
Entry point. `python -m stira.main --socket-path <path>`. Spins NSRunLoop on main thread when pyobjc available (so NSWorkspace notifications fire). Socket server on worker thread. SIGTERM handler. Logs to `~/Library/Application Support/Stira/hermes.log`.

### `hermes/stira/policy_receiver.py`
Unix domain socket server at `~/Library/Application Support/Stira/hermes.sock`. Reads newline-delimited JSON. Dispatches to `on_start_session(task_spec, emitter)`, `on_stop_session(session_id)`, `on_unknown(message)`. Creates parent dir if missing.

### `hermes/stira/event_emitter.py`
Thread-safe (threading.Lock). Writes newline-delimited JSON events back over socket. Per-connection (created fresh per client). BrokenPipeError caught silently. All events include `type`, `session_id`, `timestamp` (ISO 8601 UTC).

### `hermes/stira/session_controller.py`
`SessionController(task_spec, emitter)`. Validates `spec_version == "1.0"`. `start()` initialises three skills with rollback on partial failure. `stop()` tears down skills gracefully, emits `session_ended`.

### `hermes/stira/skills/`
- `app_suppressor.py` — `AppSuppressor(blocked_bundle_ids, on_blocked)`. NSWorkspace `didActivateApplicationNotification` subscription. pyobjc optional (graceful ImportError).
- `focus_killer.py` — `FocusKiller()`. `kill_focus(pid)` switches focus to Finder. pyobjc optional.
- `app_monitor.py` — `AppMonitor(on_app_opened)`. NSWorkspace activation/launch notifications. pyobjc optional.

### `hermes/tests/`
16 tests: socket protocol (12) + session controller (4 + integration test for on_blocked→kill_focus→emit_focus_killed chain).

---

## What Task 5 Built

### `stira-macos/Package.swift`
Swift Package Manager with two `executableTarget`s: `Stira` (macOS 14+) and `StiraExtensionBridge`.

### `stira-macos/Sources/Stira/App/StiraApp.swift`
`@main App`. RAM check (< 8GB → alert + exit) in `.onAppear`. Switches between `IntentInputView` and `SessionStatusView` based on `sessionManager.state`. `EscapeHatchView` as an `.interactiveDismissDisabled` sheet when state == `.escapeHatch`.

### `stira-macos/Sources/Stira/PolicyStore/PolicyStore.swift`
`@MainActor ObservableObject`. Sole writer of `~/Library/Application Support/Stira/active-policy.json`. Methods: `setActivePolicy(_:)`, `clearPolicy()`, `applyException(_:)`.

### `stira-macos/Sources/Stira/SessionManager/SessionManager.swift`
`@MainActor ObservableObject`. State enum: `idle | starting | active | escapeHatch | ending`. Calls Ollama `/api/generate` (qwen3:8b, `stream: false`), validates as `StiraPolicy`, starts Hermes socket, drives escape hatch. Audit log written to `~/Library/Application Support/Stira/sessions/{session_id}/audit.jsonl`.

### `stira-macos/Sources/Stira/SessionManager/EscapeHatchController.swift`
`@MainActor ObservableObject`. State machine: `idle → countdown(remaining:) → reasonEntry → granted`. 30-second Timer countdown (uncancellable). Validates reason ≥ 20 chars. `submitReason() -> ScopedException?`.

### `stira-macos/Sources/Stira/HermesSocket/HermesSocket.swift`
Async POSIX Unix socket IPC. `SO_NOSIGPIPE` set. Per-session `AsyncStream<HermesEvent>` via `AsyncStream.makeStream()` — fresh stream each `startSession`. `Darwin.shutdown(SHUT_RD)` before close so `readEventLoop` exits cleanly. 10-retry connect with 500ms backoff.

### `stira-macos/Sources/Stira/ExtensionBridge/ExtensionBridge.swift`
No-op — `PolicyStore` is the sole writer of `active-policy.json`, which `StiraExtensionBridge` reads directly.

### `stira-macos/Sources/Stira/UI/`
- `IntentInputView.swift` — multiline TextField, "Start Session" button, ProgressView during parse, error display
- `SessionStatusView.swift` — elapsed time, "End Session", "I need a break" (passes last Hermes bundle ID as target)
- `EscapeHatchView.swift` — immovable countdown circle, neutral text, reason TextField with char count, Submit disabled until ≥ 20 chars

### `stira-macos/Sources/StiraExtensionBridge/main.swift`
Chrome native messaging host. POSIX blocking `read()` for 4-byte LE length prefix + JSON body. Reads `active-policy.json`, extracts URL rules, responds as `policy` or `session_ended`. Malformed frames skip-and-continue; EOF exits cleanly. Background thread polls `active-policy.json` every 1s — pushes `policy_update` when the file is written (session start) and `session_ended` when it is deleted (session end). Stdout writes serialized via `NSLock`.

---

## What Task 4 Built

### `browser-extension/manifest.json`
Chrome MV3 manifest. Permissions: `declarativeNetRequest`, `declarativeNetRequestWithHostAccess`, `nativeMessaging`. Host permissions: `<all_urls>`. Background service worker points to `dist/background/service_worker.js` (esbuild-bundled output). Dynamic-only rules (`rule_resources: []`).

### `browser-extension/rules/rule_builder.ts`
```typescript
export function buildDNRRules(urlRules: ExtensionUrlRule[]): DNRRule[]
```
Block rules at priority=1, allow rules (exceptions) at priority=2 — allow always wins. `resourceTypes: chrome.declarativeNetRequest.ResourceType[]`. Rule IDs are sequential unique positive integers starting at 1.

### `browser-extension/background/service_worker.ts`
Connects to native messaging host `com.stira.extensionbridge` on `onStartup` and `onInstalled`. Sends `{"type": "get_policy", "client_id": "stira-extension"}`. Handles `policy` → apply rules, `policy_update` → re-apply rules, `session_ended` → clear all rules. Clears rules on disconnect.

### `scripts/install-native-messaging.sh`
Installs Chrome native messaging host manifest at `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.stira.extensionbridge.json`. Takes extension ID as `$1`. Points to `/Applications/Stira.app/Contents/MacOS/StiraExtensionBridge`.

### Build tooling
`esbuild` bundles `background/service_worker.ts` → `dist/background/service_worker.js`. `tsconfig.json` is type-check only (`noEmit: true`). `tsconfig.test.json` provides CommonJS + jest types for Jest runs.

---

## Task 3: What To Build Next (Hermes Modification) [COMPLETED]

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
- **Wait for sign-off before starting next task** — do not auto-proceed
- If user says "proceed" or "approved", start the next task

Use `superpowers:subagent-driven-development`. Fresh subagent per task. Spec compliance review first, then code quality review. Fix any issues before marking complete.

---

## How To Verify Current State

```bash
# Confirm 20/20 tests pass
cd /Users/ronith/Documents/Projects/Stira/intent-engine
python3 -m pytest tests/ -v

# Confirm git log
git log --oneline
# 2977d8b docs: add HANDOFF.md for session continuity
# 746f7bf feat: add Ollama/qwen3:8b intent engine with constrained JSON decoding
# 13d31ea fix: remove unused datetime import
# caf5b84 feat: add StiraPolicy schema with Python and Swift type definitions
# df33af8 chore: initial project setup
```

---

## Open Notes From Reviews

- **Task 2 quality review flagged:** `parse_intent()` accepts empty strings — caller should trim/validate `raw_intent` before passing. The Session Manager (Task 5) must do this validation.
- **Task 1 quality review noted:** `to_dict()` return annotations were already present (reviewer was wrong); unused `datetime` import was removed in fix commit `13d31ea`.
- **Schema IDE warning:** VS Code may flag the JSON Schema `$schema` draft-07 URL as unresolvable — this is a false positive. The schema is valid JSON and passes `jsonschema.Draft7Validator`.

---

## Key Files To Read Before Starting

1. [CLAUDE.md](CLAUDE.md) — all product and architecture decisions (authoritative, read this first)
2. [HANDOFF.md](HANDOFF.md) — this file
3. [docs/schema/stira-policy.schema.json](docs/schema/stira-policy.schema.json) — central data structure
4. [docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md](docs/superpowers/plans/2026-05-26-stira-mvp-implementation.md) — full implementation plan with code for all 6 tasks
