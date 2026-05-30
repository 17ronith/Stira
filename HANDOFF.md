# Stira MVP — Session Handoff

**Date:** 2026-05-28  
**Branch:** master  
**Last commit:** `dd08a62` fix: unblock main thread in readEventLoop; add Dock re-open handler

---

## Start Here (Paste Into New Session)

```
Read HANDOFF.md, then CLAUDE.md. We're building the Stira MVP.
Tasks 1–6 are done (43/43 Python+JS tests, 15/15 Swift tests passing).
The app runs end-to-end. Several pre-MVP gaps from CLAUDE.md still need
addressing before it's demo-ready. Pick up from the Pre-MVP Gaps section
in HANDOFF.md — start with whichever the user asks for.
```

---

## Task List

- [x] **Task 1** — Policy Schema: `stira-policy.schema.json`, `stira_policy.py`, `StiraPolicy.swift` — 10/10 tests
- [x] **Task 2** — Intent Engine: `intent_engine.py`, `prompt_builder.py` — 10/10 tests (20/20 total)
- [x] **Task 3** — Hermes Modification: Unix socket server/emitter + 3 enforcement skills — 16/16 tests (36/36 total)
- [x] **Task 4** — Browser Extension: Chrome MV3, `declarativeNetRequest`, path-level exceptions — 7/7 tests (43/43 total)
- [x] **Task 5** — SwiftUI Native App: intent input, session manager, escape hatch UX — `swift build` ✅
- [x] **Task 6** — Installer + First-Run: Ollama bundle, qwen3:8b pull progress bar, Accessibility onboarding ✅

**Total tests passing:** 43/43 Python+JS · 15/15 Swift XCTest  
**Acceptance criterion:** 10-second test (intent → visible enforcement, one permission ask)

---

## What Stira Is

Local-first macOS focus app. User types intent in plain language → local LLM produces a JSON policy → macOS enforcement (Hermes subprocess) blocks distracting apps → Chrome extension blocks URLs. No cloud during sessions. Full context in [CLAUDE.md](CLAUDE.md).

---

## Current Build State

| Component | Status | Notes |
|-----------|--------|-------|
| Policy Schema (JSON Schema + Python + Swift) | ✅ Done | |
| Intent Engine (Ollama + qwen3:8b constrained decoding) | ✅ Done | |
| Hermes Modification (Unix socket + 3 enforcement skills) | ✅ Done | |
| Browser Extension (Chrome MV3, declarativeNetRequest) | ✅ Done | |
| SwiftUI Native App (intent input, session manager, escape hatch) | ✅ Done | |
| Installer + First-Run Flow (Ollama bundle, model pull, permissions) | ✅ Done | |
| Stability fixes (crash recovery, timer leak, session timeout) | ✅ Done | See below |
| UI responsiveness (main thread unblocked) | ✅ Done | See below |

**Tests:**
```bash
# Intent engine (20 tests)
cd /Users/ronith/Documents/Projects/Stira/intent-engine && python3 -m pytest tests/ -v

# Hermes (16 tests)
cd /Users/ronith/Documents/Projects/Stira/hermes && python3 -m pytest tests/ -v

# Browser extension (7 tests)
cd /Users/ronith/Documents/Projects/Stira/browser-extension && npx jest

# Swift (15 tests)
cd /Users/ronith/Documents/Projects/Stira/stira-macos && swift test
```

---

## Stability Fixes Landed (2026-05-28)

### Bug 1: Hermes crash left session stuck in `.active` forever
- **Root cause:** No `Process.terminationHandler` on the Hermes subprocess.
- **Fix:** `SessionManager.launchHermes()` now sets `terminationHandler` before `process.run()`. Handler dispatches `handleHermesCrash(exitCode:)` back to `@MainActor`. The method guards on `state == .active || .escapeHatch` to avoid double-reset during normal `.ending` shutdown.
- **File:** `stira-macos/Sources/Stira/SessionManager/SessionManager.swift`

### Bug 2: EscapeHatch countdown timer leaked after session end
- **Root cause:** `EscapeHatchController.countdownTimer` (a `Timer`) was never invalidated when a session ended.
- **Fix:** Added `reset()` to `EscapeHatchController` that invalidates and nils the timer and clears all state. Called in both `endSession()` and `handleHermesCrash()`.
- **File:** `stira-macos/Sources/Stira/SessionManager/EscapeHatchController.swift`

### Bug 3: Sessions never auto-terminated after their policy duration
- **Root cause:** `policy.session.durationMinutes` was included in the task spec but nothing enforced the timeout.
- **Fix:** After `state = .active`, `SessionManager` creates a `Task<Void, Never>?` stored as `sessionTimeoutTask`. It sleeps `durationMins * 60` seconds then calls `endSession()`. Cancelled at start of `endSession()`, in the error catch, and in `handleHermesCrash()`. `durationMinutes == 0` means indefinite (no task created).
- **File:** `stira-macos/Sources/Stira/SessionManager/SessionManager.swift`

### Bug 4: `AppRule` decoding crashed when LLM omitted `display_name`
- **Root cause:** LLM (qwen3:8b) occasionally omits the `display_name` field from app objects in the policy JSON. `AppRule` had no custom decoder, so `JSONDecoder` threw and the entire session start failed.
- **Fix:** Added custom `init(from:)` to `AppRule` using `(try? c.decode(...)) ?? ""` fallback for `displayName`, matching the defensive pattern already used by `UrlRule`.
- **File:** `stira-macos/Sources/Stira/Models/StiraPolicy.swift`

### Bug 5: Beachball / frozen UI during active session
- **Root cause:** `readEventLoop()` is a method of `@MainActor final class HermesSocket`. Despite being launched via `Task.detached`, Swift dispatches any isolated method back to its actor — so `Darwin.read()` was blocking the main thread the entire session.
- **Fix:** Changed `readEventLoop` to `nonisolated` and passes `fd: Int32` as a parameter. Uses a local `JSONDecoder` (no actor-isolated state). Main actor is only touched briefly via `await MainActor.run { }` to publish decoded events. `Task.detached` now actually runs off main.
- **File:** `stira-macos/Sources/Stira/HermesSocket/HermesSocket.swift`

### Bug 6: Clicking app icon didn't bring window to foreground
- **Root cause:** No `NSApplicationDelegate` handler for `applicationShouldHandleReopen`, so clicking the Dock icon while Stira was backgrounded had no effect.
- **Fix:** Added `AppDelegate: NSObject, NSApplicationDelegate` in `StiraApp.swift` with `applicationShouldHandleReopen` that calls `makeKeyAndOrderFront` + `activate`. Wired via `@NSApplicationDelegateAdaptor`.
- **File:** `stira-macos/Sources/Stira/App/StiraApp.swift`

---

## Pre-MVP Gaps (from CLAUDE.md — Ordered by Priority)

Items still outstanding. The app works end-to-end but these need addressing before a public demo.

### Functional Gaps

1. **[BLOCKING] pyobjc not bundled or auto-installed** — Hermes's enforcement skills silently no-op if `pyobjc` is missing. Developer workaround: `cd hermes && pip install -e ".[macos]"`. Distribution requires automating this in setup flow or bundling.

2. **[BLOCKING] StiraExtensionBridge binary not built or bundled** — The native messaging manifest correctly points to `StiraExtensionBridge` beside the main executable, but it needs to be built and present for the Chrome extension to receive policies. Without it the extension is inert.

3. **Python not available on user machines** — `findPython()` checks Homebrew paths and `/usr/bin/python3`. Most users don't have Python. Distribution requires bundling a Python runtime or using a PyInstaller-built Hermes binary.

4. **`findPython()` returns `/usr/bin/python3` stub on macOS** — On macOS, `/usr/bin/python3` is an Xcode tools stub that prompts for installation rather than running. `fileExists` returns true for the stub. Should validate by running `python3 --version` or checking for real site-packages.

5. **Hermes crash recovery watchdog** — `handleHermesCrash()` now correctly resets state, but there's no restart/watchdog. If Hermes crashes mid-session, enforcement stops and the user has to manually start a new session. A restart-with-backoff loop would improve robustness.

### UI/UX Gaps

6. **`IntentInputView` is bare** — No branding, no example intent chips, no visual hierarchy. Needs: app wordmark, 2–3 example chips ("focus on coding", "write without distractions", "deep reading"), subtle submission animation.

7. **`SessionStatusView` lacks remaining time** — Shows elapsed but not `X minutes remaining`. Should show countdown in the last 5 minutes with a warning state.

8. **No session intent summary** — Once active, user can't see what apps/URLs are blocked. Should show the policy intent label and a collapsed list.

9. **Escape hatch target picker is wrong** — "I need a break" uses `lastHermesEvent?.bundleId` (last *blocked* app) as the exception target. Should present a picker or text field for the specific app the user wants to open.

10. **No menu bar icon** — For a focus tool, a menu bar presence (status icon showing session active/idle) is table-stakes UX.

### Distribution & Signing

11. **No code signing configuration** — Debug builds break AX permission on every rebuild (TCC ties entry to binary hash). Production requires Developer ID signing + Xcode signing configuration.

12. **Hermes not bundled in app Resources** — For distribution, `hermes/` must be embedded at `Stira.app/Contents/Resources/hermes/`. `hermesRoot()` already handles this path, but the Xcode build phase to copy the directory doesn't exist.

13. **Chrome extension not published** — Extension ID `kceccioddldmaiodjklbpfmlmiogcbkb` is hardcoded. Needs to be published to Chrome Web Store under that ID, or installed as unpacked developer extension. For distribution, confirm the ID.

---

## Git Log (Recent)

```
dd08a62 fix: unblock main thread in readEventLoop; add Dock re-open handler
3c2e1a9 fix: tolerate missing display_name in AppRule JSON from LLM
aa2d0e9 fix: call escapeHatchController.reset() in endSession to stop leaked timer
09019dc fix: wire terminationHandler on Hermes Process for crash recovery
49ef4c8 fix: enforce session duration via Task-based timeout in startSession
74eeff3 fix: add handleHermesCrash() and sessionTimeoutTask to SessionManager
dba0a66 fix: add EscapeHatchController.reset() to stop leaked countdown timer
45cf3b3 test: add StiraTests XCTest target to Package.swift
13276f5 fix: close connection socket in finally block to prevent fd leak
1a0c54b chore: remove dead code — PolicySchema.schemaJSON and intent-engine Python package
df9fda6 fix: launch brew-installed Ollama via 'ollama serve' subprocess if app bundle absent
d55b98a feat: install native messaging manifest during onboarding
32127f6 fix: address code review issues in apply_exception
d670232 feat: add apply_exception IPC message to propagate escape hatch to Hermes
99e593c feat: add installer and first-run onboarding flow
```

---

## Architecture Decisions (Final — Do Not Relitigate)

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

---

## Implementation Notes — All Runtime Bugs Found and Fixed

### Hermes subprocess was never launched (CRITICAL)
`SessionManager.startSession()` called `hermesSocket.startSession()` directly without first launching the Hermes Python subprocess. Fixed by adding `launchHermes()` at the top of `startSession()`.

### Escape hatch exceptions never reached Hermes (CRITICAL)
`handleEscapeHatchGrant()` updated the in-Swift `PolicyStore` but never sent `apply_exception` over the Unix socket. Fixed by adding the `apply_exception` IPC message type wired through `policy_receiver.py` → `session_controller.py` → `app_suppressor.unblock()`.

### `hermesRoot()` walked too few directory levels (CRITICAL for `swift run`)
The binary at `stira-macos/.build/debug/Stira` needs 3 levels up to reach `stira-macos/`; arm64 variant needs 5. Fixed: iterate up to 6 levels, return first ancestor containing `hermes/`.

### Native messaging manifest installed at dev path (HIGH)
`OnboardingCoordinator.installNativeMessagingManifest()` now writes the manifest at the end of onboarding, pointing to the actual `StiraExtensionBridge` binary alongside the running executable.

### `AppSuppressor` race condition on `blocked_bundle_ids` (HIGH)
List was read on NSRunLoop (app activate notifications) and mutated from socket serve thread. Fixed with `threading.Lock` protecting all reads and writes.

### `AXIsProcessTrusted()` unreliable on macOS 26 for debug builds (PLATFORM BUG)
TCC ties accessibility entries to the binary's code hash. Every `swift build` invalidates the old entry. Workaround: call `AXIsProcessTrustedWithOptions(prompt: true)` to register the current binary; add `DistributedNotificationCenter` listener; add manual "I've granted permission — continue" button that bypasses the check. Production builds with stable Developer ID signing are unaffected.

### Unix socket fd leak
`policy_receiver._serve_connection()` lacked `finally: conn.close()`. Fixed with `try/finally`.

### `Darwin.read()` blocking main thread
`readEventLoop()` was `@MainActor` (all methods of an `@MainActor` class are, regardless of `Task.detached`). Changed to `nonisolated func readEventLoop(fd: Int32)` with a local `JSONDecoder`. Main actor only touched for event publishing.

### `AppRule` missing `display_name` fallback
LLM occasionally omits `display_name` from app objects. Added custom `init(from:)` with `(try? ...) ?? ""` fallback, matching `UrlRule`'s existing pattern.

---

## Hermes Python Dependencies

```bash
cd /Users/ronith/Documents/Projects/Stira/hermes && pip install -e ".[macos,dev]"
```

Required for enforcement. Skills no-op silently if pyobjc absent (correct for CI, wrong for production).

---

## Key Files

```
stira/
├── CLAUDE.md                                         ← source of truth for ALL decisions
├── HANDOFF.md                                        ← this file
├── docs/schema/stira-policy.schema.json              ← central policy schema
└── stira-macos/
    ├── Package.swift                                 ← SPM: StiraCore + Stira + StiraExtensionBridge + StiraTests
    ├── Sources/
    │   ├── Stira/
    │   │   ├── App/StiraApp.swift                    ← @main, AppDelegate, WindowGroup
    │   │   ├── Models/StiraPolicy.swift              ← Codable policy structs
    │   │   ├── SessionManager/SessionManager.swift   ← session lifecycle, Ollama call, Hermes subprocess
    │   │   ├── SessionManager/EscapeHatchController.swift  ← 30s countdown, reason validation
    │   │   ├── HermesSocket/HermesSocket.swift       ← Unix socket IPC (nonisolated readEventLoop)
    │   │   ├── PolicyStore/PolicyStore.swift         ← sole writer of active-policy.json
    │   │   ├── Onboarding/OnboardingCoordinator.swift
    │   │   └── UI/                                   ← IntentInputView, SessionStatusView, EscapeHatchView
    │   ├── StiraApp/main.swift                       ← sets .regular activation policy, calls StiraApp.main()
    │   └── StiraExtensionBridge/main.swift           ← Chrome native messaging host
    └── Tests/StiraTests/
        ├── EscapeHatchControllerTests.swift          ← 4 tests (timer leak regression)
        ├── SessionManagerCrashTests.swift            ← 6 tests (crash recovery guards)
        ├── SessionTimeoutTests.swift                 ← 4 tests (timeout task math/cancellation)
        └── PackageTests.swift                        ← 1 smoke test
```
