# Stira — Full Engineering Context

Complete reference for any engineer (or AI agent) continuing this project. Covers every component, every file, every protocol, every known bug, and every design decision made so far. Written to be self-contained: reading this plus the CLAUDE.md is sufficient to understand and continue the codebase.

---

## 1. What Stira Is

Stira is a local-first macOS desktop application that reshapes a user's digital environment based on declared intent. The user types what they want to focus on in plain language ("coding session", "write without distractions"), and Stira:

1. Interprets the intent via a local LLM (qwen3:8b via Ollama) and produces a structured policy object
2. Enforces that policy for the session — blocking named apps from foregrounding, killing their focus, monitoring what the user opens
3. Applies URL blocking rules in Chrome via a browser extension
4. Shows blocked-app toast notifications when an enforcement event fires

**The competitive difference:** every existing focus tool (Cold Turkey, Freedom, Apple Focus) is rule-based where the user manually authors the rules. Stira is rule-based where the AI authors the rules from a single natural language declaration.

**MVP acceptance criterion (10-second test):** user declares intent → environment visibly changes → within 10 seconds → with one permission ask. This is the standard every change should be evaluated against.

---

## 2. Repository Layout

```
Stira/
├── stira-macos/           Swift package — macOS app + extension bridge
│   ├── Package.swift
│   ├── Sources/
│   │   ├── Stira/         Library target (StiraCore) — all app logic and UI
│   │   │   ├── App/           StiraApp.swift — root SwiftUI app entry
│   │   │   ├── Models/        StiraPolicy.swift — central data model
│   │   │   ├── PolicyStore/   PolicyStore.swift — in-memory + disk policy
│   │   │   ├── SessionManager/ SessionManager.swift, EscapeHatchController.swift
│   │   │   ├── HermesSocket/  HermesSocket.swift — Unix socket IPC client
│   │   │   ├── Onboarding/    OnboardingCoordinator, OllamaInstaller, views
│   │   │   ├── ExtensionBridge/ ExtensionBridge.swift (minimal placeholder)
│   │   │   └── UI/            IntentInputView, SessionStatusView, EscapeHatchView,
│   │   │                       GlassModifiers
│   │   ├── StiraApp/      Executable target — just calls StiraApp.main()
│   │   └── StiraExtensionBridge/  Chrome native messaging host binary
│   └── Tests/StiraTests/  Swift unit tests
├── hermes/                Python enforcement backend
│   ├── pyproject.toml
│   └── stira/
│       ├── main.py        Entry point — socket server + signal/watchdog setup
│       ├── policy_receiver.py  Unix socket server
│       ├── session_controller.py  Orchestrates the three skills
│       ├── event_emitter.py  Writes HermesEvents back to Swift
│       └── skills/
│           ├── app_suppressor.py  NSWorkspace block enforcement
│           ├── focus_killer.py    Activates Finder to kill blocked app focus
│           └── app_monitor.py     Logs all app activations
├── browser-extension/     Chrome extension (TypeScript)
│   ├── manifest.json
│   ├── background/service_worker.ts   Handles native messaging + DNR rules
│   ├── rules/rule_builder.ts          Converts policy URL rules to Chrome DNR
│   └── dist/              Compiled JS (committed — no build step for end users)
├── intent-engine/         Standalone Python intent-engine package (not used at
│   └── src/               runtime; Swift app calls Ollama directly)
├── docs/
│   └── schema/stira-policy.schema.json  JSON Schema for StiraPolicy
└── scripts/
    └── install-native-messaging.sh
```

---

## 3. The StiraPolicy — Central Data Structure

Everything in the system either produces or consumes a `StiraPolicy`. Get this schema right before touching anything else.

### JSON shape (snake_case, mirrors Swift CodingKeys)

```json
{
  "schema_version": "1.0",
  "session_id": "<UUID>",
  "intent": {
    "raw": "coding session",
    "normalised": "coding session",
    "confidence": 0.95
  },
  "session": {
    "duration_minutes": 120,
    "hard_stop": false
  },
  "apps": {
    "mode": "block_listed",
    "blocked": [
      {"bundle_id": "com.hnc.Discord", "display_name": "Discord"},
      {"bundle_id": "net.whatsapp.WhatsApp", "display_name": "WhatsApp"}
    ],
    "allowed": []
  },
  "urls": {
    "rules": [
      {"pattern": "twitter.com", "action": "block", "reason": "social media", "exceptions": []},
      {"pattern": "youtube.com", "action": "block", "reason": "entertainment",
       "exceptions": [{"pattern": "youtube.com/watch", "reason": "lecture exception"}]}
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
```

### Swift representation (`stira-macos/Sources/Stira/Models/StiraPolicy.swift`)

- `struct StiraPolicy: Encodable, Equatable` — primary declaration uses `Encodable` only
- `extension StiraPolicy: Decodable` — in a SEPARATE extension to preserve synthesized memberwise init. If `init(from:)` is placed in the struct body it suppresses the synthesized init and breaks `StiraPolicy.example`. This is a load-bearing constraint — do not move it.
- Lenient decoding: `urls`, `notifications`, `escape_hatch` are decoded with `try?` and fall back to safe defaults — the model sometimes omits trailing sections when running long
- All enums have custom `init(from:)` with fallback defaults (unknown `AppMode` → `.blockListed`, etc.)
- `UrlAction` decoder trims whitespace and lowercases before matching — Ollama occasionally produces ` nad` or `" block"` garbage

### Persistence

- `PolicyStore.setActivePolicy(_:)` writes the policy to `~/Library/Application Support/Stira/active-policy.json` atomically
- `PolicyStore.clearPolicy()` deletes that file
- `StiraExtensionBridge` reads and watches `active-policy.json` directly — no other IPC to the extension

---

## 4. Component: Swift/SwiftUI macOS App

**Swift Package targets:**
- `StiraCore` — library with all app logic; `path: Sources/Stira`
- `Stira` — executable, just calls `StiraApp.main()`; `path: Sources/StiraApp`
- `StiraExtensionBridge` — separate executable for Chrome native messaging; `path: Sources/StiraExtensionBridge`
- `StiraTests` — test target depending on `StiraCore`

**Platform:** macOS 14+, Swift 5.9+

### 4.1 App Entry and Root View (`StiraApp.swift`)

```swift
// Root view switching logic:
switch sessionManager.state {
case .idle, .starting:                   IntentInputView()
case .active, .escapeHatch, .ending:     SessionStatusView()
}

// Escape hatch sheet:
.sheet(isPresented: Binding(get: { sessionManager.state == .escapeHatch }, set: { _ in })) {
    EscapeHatchView(controller: sessionManager.escapeHatchController)
        .interactiveDismissDisabled(true)
}
```

Window style: `.hiddenTitleBar` + `.windowResizability(.contentSize)`. `WindowConfigurator` (NSViewRepresentable) makes the window transparent: `window.isOpaque = false`, `window.backgroundColor = .clear`, `window.styleMask.insert(.fullSizeContentView)`.

### 4.2 SessionManager (`SessionManager.swift`)

`@MainActor final class SessionManager: ObservableObject`

**Key state:**
```swift
@Published var state: SessionState        // idle/starting/active/escapeHatch/ending
@Published var errorMessage: String?
@Published var sessionStartTime: Date?
@Published var lastHermesEvent: HermesEvent?
let policyStore = PolicyStore()
let escapeHatchController = EscapeHatchController()
private var hermesSocket = HermesSocket()
private var hermesProcess: Process?
var sessionTimeoutTask: Task<Void, Never>?
```

**`startSession(rawIntent:durationMinutes:)` flow:**
1. `launchHermes()` — kills orphan `stira.main` processes via `pkill`, starts new Python subprocess
2. `await Task.sleep(500ms)` — give Hermes time to bind its socket
3. `callOllama(rawIntent:)` — POST to `http://localhost:11434/api/generate`
4. `policyStore.setActivePolicy(policy)` — writes `active-policy.json`
5. `hermesSocket.startSession(taskSpec)` — connects Unix socket, sends `start_session` JSON, starts `readEventLoop` in `Task.detached`
6. `state = .active`, starts session timeout `Task` if `durationMinutes > 0`
7. Starts event consumer `Task` that iterates `hermesSocket.events` and sets `lastHermesEvent`

**`endSession()` flow:**
1. Cancels `sessionTimeoutTask`
2. `hermesSocket.stopSession(sessionId:)` — shuts down socket read side, sends `stop_session`, closes fd
3. `writeAuditLog(sessionId:)` — writes `~/Library/Application Support/Stira/sessions/<id>/audit.jsonl`
4. `policyStore.clearPolicy()` — deletes `active-policy.json`
5. `hermesProcess?.terminate()` — sends SIGTERM to Hermes
6. Resets all state

**`launchHermes()`:**
- Locates Hermes root by walking up to 6 levels from executable path looking for a `hermes/` subdirectory (handles `swift run`, `swift build` arch paths, and packaged `.app`)
- Finds Python at `/opt/homebrew/bin/python3` (Apple Silicon) or `/usr/local/bin/python3` (Intel) or `/usr/bin/python3`
- Sets `PYTHONUNBUFFERED=1` so Hermes log lines flush immediately
- Registers `terminationHandler` that calls `handleHermesCrash(exitCode:)` on the main actor

**Ollama call details:**
- Model: `qwen3:8b` via `http://localhost:11434/api/generate`
- `stream: false` — waits for full response before decoding
- `format: "json"` — Ollama constrained decoding at token generation level (not prompt instruction)
- `num_predict: -1` — MUST be -1. Positive values truncate the JSON mid-object causing decode errors.
- `timeout: 180s` — qwen3:8b is slow on first run
- Ollama response envelope: `{"model":"...","response":"<JSON string>","done":true,...}` — extract `envelope.response` then decode as `StiraPolicy`
- Prompt begins with `/no_think` to suppress qwen3's chain-of-thought scratchpad
- Prompt provides explicit bundle IDs and domains for known social/distraction apps with per-intent guidance

**`handleEscapeHatchGrant()`:**
- Calls `escapeHatchController.submitReason()` → `ScopedException`
- Calls `policyStore.applyException(exception)` — updates policy in-memory and on disk
- Calls `hermesSocket.applyException(sessionId:bundleId:)` — sends `apply_exception` over socket so Hermes's `AppSuppressor.unblock()` is called

### 4.3 HermesSocket (`HermesSocket.swift`)

`@MainActor final class HermesSocket: ObservableObject`

Socket path: `~/Library/Application Support/Stira/hermes.sock`

**Messages sent Swift → Hermes (newline-delimited JSON):**
```
{"type":"start_session","policy":{<HermesTaskSpec>}}\n
{"type":"stop_session","session_id":"<uuid>"}\n
{"type":"apply_exception","bundle_id":"com.hnc.Discord"}\n
```

**Events received Hermes → Swift:**
```
{"type":"session_started","session_id":"...","timestamp":"..."}\n
{"type":"app_blocked","session_id":"...","bundle_id":"...","timestamp":"..."}\n
{"type":"focus_killed","session_id":"...","bundle_id":"...","timestamp":"..."}\n
{"type":"app_opened","session_id":"...","bundle_id":"...","timestamp":"..."}\n
{"type":"session_ended","session_id":"...","timestamp":"..."}\n
{"type":"error","session_id":"...","message":"...","timestamp":"..."}\n
```

**Key implementation details:**
- `var events: AsyncStream<HermesEvent>` — created in `init()`, reset on each new session via `resetEventStream()`
- `resetEventStream()` finishes the OLD continuation before creating a new one — prevents old consumer tasks from keeping the stream alive
- `connectWithRetry()` — 10 attempts, 500ms between attempts (up to 9 seconds total)
- `readEventLoop(fd:)` is `nonisolated` — runs in a `Task.detached` so `Darwin.read()` doesn't block the main actor. Yields events via `await MainActor.run { _eventsContinuation?.yield(event) }`
- `stopSession(sessionId:)` calls `Darwin.shutdown(socketFd, SHUT_RD)` before writing `stop_session` — this causes the blocking `Darwin.read` in `readEventLoop` to return 0 and exit cleanly

**`HermesTaskSpec` (the `policy` field in `start_session`):**
```swift
struct HermesTaskSpec: Codable {  // CodingKeys use snake_case
    let specVersion: String          // "spec_version": "1.0"
    let sessionId: String
    let blockedBundleIds: [String]
    let allowedBundleIds: [String]
    let enforcementMode: String      // "block_listed" or "allow_listed"
    let sessionDurationSeconds: Int
    let auditLevel: String           // "standard"
}
```

**`HermesEvent` (received from Hermes):**
```swift
struct HermesEvent: Codable, Equatable {
    let type: String
    let sessionId: String
    let timestamp: String    // ISO 8601
    let bundleId: String?
    let message: String?
}
```

### 4.4 IntentInputView (`UI/IntentInputView.swift`)

Shown when `state == .idle || state == .starting`:
- Multi-line `TextField` for intent text (3–6 lines, `axis: .vertical`)
- Duration picker chips: 30m / 45m / 1h / 90m / 2h (default 60m)
- "Start Xh session" button (appears with `.move(edge:.bottom).combined(with:.opacity)` when text non-empty)
- `ProgressView` + "Building your focus environment…" during `.starting`
- Error display for `sessionManager.errorMessage`
- Keyboard shortcut: `Cmd+Return`

### 4.5 SessionStatusView (`UI/SessionStatusView.swift`)

Shown when `state == .active || state == .escapeHatch || state == .ending`:
- Large thin-font elapsed time clock (ticks every 1s via `Timer.publish`)
- "X minutes remaining" pill with warning color in last 5 minutes
- Intent text label (normalised from policy)
- Blocked apps grid with real app icons
- "I need a blocked app" → triggers escape hatch
- "End Session" → confirmation dialog
- **Blocked-app toast pill** at top of view via `.overlay(alignment: .top)`

**Toast mechanics:**

```swift
@Environment(\.accessibilityReduceMotion) private var reduceMotion

.overlay(alignment: .top) {
    if showToast, let name = toastDisplayName {
        blockedToastPill(bundleId: toastBundleId, name: name)
            .transition(reduceMotion ? .opacity : .scale(scale: 0.85, anchor: .top).combined(with: .opacity))
            .padding(.top, 16)
    }
}
.onChange(of: sessionManager.lastHermesEvent) { _, event in
    guard let event, event.type == "app_blocked" || event.type == "focus_killed",
          let bundleId = event.bundleId else { return }
    triggerBlockedToast(bundleId: bundleId, displayName: name)
}
```

`triggerBlockedToast()`:
1. `NSApp.activate(ignoringOtherApps: true)` — CRITICAL: `FocusKiller` activates Finder after every block, pushing Stira's window behind Finder. Without this the toast renders but is invisible.
2. `NSApp.windows.first(where: { !$0.isMiniaturized })?.makeKeyAndOrderFront(nil)`
3. `withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) { showToast = true }`
4. Schedules a dismiss `Task` after 3.5 seconds
5. `glassCard(cornerRadius: 20, fillOpacity: 0.3)` — pill background is 30% white opacity for legibility

### 4.6 EscapeHatchController + EscapeHatchView

Four-phase Standard-mode flow:
1. `.appPicker` — list of installed blocked apps (filtered via `NSWorkspace`) + custom app name text field
2. `.countdown(remaining: Int)` — 30-second immovable circular countdown timer
3. `.reasonEntry` — text field requiring ≥20 characters (`isReasonValid: reason.count >= 20`)
4. `.granted` — confirmation with optional "Open App" button

`EscapeHatchController.submitReason()` returns `ScopedException` (30-minute exception). `SessionManager.handleEscapeHatchGrant()` applies it to both `PolicyStore` and Hermes.

### 4.7 Onboarding Flow (`Onboarding/`)

`OnboardingCoordinator` drives: `checkingRAM → installingOllama → downloadingModel(progress) → awaitingPermission → complete`

- **RAM check:** < 8GB → `.failed(...)`
- **Ollama:** `OllamaInstaller.ensureOllama()` — checks if `ollama` CLI available, installs if needed, starts `ollama serve` if not running. Tries Homebrew paths + GUI app.
- **Model pull:** `OllamaInstaller.pullModel("qwen3:8b")` — streams progress via callback. Guards against stale callbacks after step advances.
- **Accessibility:** `isAccessibilityFunctional()` uses `AXUIElementCopyAttributeValue(AXUIElementCreateSystemWide(), kAXFocusedApplicationAttribute, &value)`. Polls every 1s + `com.apple.accessibility.api` distributed notification. Manual bypass button calls `permissionTrigger?.finish()`.
- **Native messaging manifest:** writes `~/Library/Application Support/Google/Chrome/NativeMessagingHosts/com.stira.extensionbridge.json`

### 4.8 GlassModifiers (`UI/GlassModifiers.swift`)

```swift
func glassCard(cornerRadius: CGFloat = 16, fillOpacity: Double = 0.08) -> some View
// Applies: .ultraThinMaterial + Color.white.opacity(fillOpacity) + .clipShape + border stroke

struct GlassButtonStyle: ButtonStyle     // Scale press effect (0.97x)
struct WindowConfigurator: NSViewRepresentable   // Makes window transparent
struct AppBackground: View               // Dark gradient for previews
```

### 4.9 StiraExtensionBridge (`Sources/StiraExtensionBridge/main.swift`)

Separate executable binary (Chrome native messaging host protocol — 4-byte LE length + JSON):
- On `get_policy` message: reads `active-policy.json`, extracts URL rules, responds `{type:"policy", rules:[...]}`
- Background thread polls `active-policy.json` every 1s: pushes `policy_update` on change, `session_ended` on deletion
- Thread-safe stdout writes via `NSLock`

---

## 5. Component: Hermes Python Backend

**Location:** `hermes/`
**Python:** ≥ 3.11
**Required packages (macOS enforcement):** `pyobjc-framework-Cocoa`, `pyobjc-framework-ApplicationServices`

Install: `cd hermes && pip install -e ".[macos,dev]"`

Run: `python -m stira.main` from the `hermes/` directory (invoked by `SessionManager.launchHermes()`)

Logs: `~/Library/Application Support/Stira/hermes.log`

### 5.1 main.py

Entry point. Key setup:
1. Logging (file + stderr)
2. `PolicyReceiver` socket server
3. Monkey-patches `receiver._serve_connection` with `_serve_connection_with_emitter` — wires a per-connection `EventEmitter` so all events flow back on the same socket the session was started on
4. **SIGTERM handler** → `_shutdown()` — triggered by `hermesProcess.terminate()` from Swift
5. **SIGINT handler** → `_shutdown()` — catches Ctrl+C sent to the swift run process group
6. **Parent PID watchdog thread** — polls `os.getppid()` every 2s; if Stira crashes/force-quits, the ppid changes to launchd and the watchdog calls `os._exit(0)`. This prevents Hermes orphans from continuing to block apps.
7. NSRunLoop spin on main thread (required for NSWorkspace notifications to fire)

`_shutdown(reason)`:
- Stops active `SessionController` (unregisters NSWorkspace observers → stops blocking immediately)
- Stops `PolicyReceiver`
- Calls `os._exit(0)` (avoids raising SystemExit into Objective-C NSRunLoop which causes OC_PythonException crashes)

### 5.2 policy_receiver.py

Unix socket server. Key behaviors:
- `start()`: removes stale socket file with `os.unlink`, binds, listens, spawns accept loop thread
- `stop()`: closes server socket. Does NOT call `os.unlink()` — this would race with a concurrently-launching new Hermes (pkill returns before old Hermes finishes its SIGTERM handler; the unlink could delete the new socket)
- Per connection: `_serve_connection_with_emitter(conn)` creates `EventEmitter(conn.makefile("w"))`, reads from `conn.makefile("r")` in a for loop
- Dispatches: `start_session`, `stop_session`, `apply_exception`

### 5.3 session_controller.py

Orchestrates the three enforcement skills for one session.

`start()`:
1. Creates `FocusKiller` (stateless)
2. Creates `AppSuppressor(blocked_bundle_ids=[...], on_blocked=callback)` where callback emits `app_blocked`, looks up PID, calls `focus_killer.kill_focus(pid)`, emits `focus_killed`
3. Creates `AppMonitor(on_app_opened=callback)` — emits `app_opened` for every app activation
4. Starts suppressor and monitor
5. Emits `session_started`

`apply_exception(bundle_id)`: calls `_suppressor.unblock(bundle_id)`

`stop()`: stops both skills, emits `session_ended`

### 5.4 Skills

**AppSuppressor (`skills/app_suppressor.py`):**
- Subscribes to `NSWorkspaceDidActivateApplicationNotification`
- When blocked app activates: calls `on_blocked(bundle_id)`
- `unblock(bundle_id)` removes the ID from `blocked_bundle_ids` (protected by `threading.Lock`)
- No-op if pyobjc unavailable

**FocusKiller (`skills/focus_killer.py`):**
- `kill_focus(pid)`: activates Finder via `NSWorkspace`
- Side effect: Finder comes to front, pushing Stira's window behind it. The Swift `triggerBlockedToast()` compensates with `NSApp.activate(ignoringOtherApps: true)`.

**AppMonitor (`skills/app_monitor.py`):**
- Subscribes to `NSWorkspaceDidActivateApplicationNotification` AND `NSWorkspaceDidLaunchApplicationNotification`
- Calls `on_app_opened(bundle_id)` for all app events (audit trail)

### 5.5 event_emitter.py

Writes newline-terminated JSON to `conn.makefile("w")`. Calls `flush()` after every write. Thread-safe via `threading.Lock`. Catches `BrokenPipeError`, `OSError`, `ValueError`.

---

## 6. Component: Browser Extension

**Location:** `browser-extension/`
**Manifest Version:** 3
**Extension ID:** `kceccioddldmaiodjklbpfmlmiogcbkb`
**Permissions:** `declarativeNetRequest`, `declarativeNetRequestWithHostAccess`, `nativeMessaging`, `<all_urls>`

### Session flow

1. On install/startup: `chrome.runtime.connectNative("com.stira.extensionbridge")`
2. Sends `{type:"get_policy"}` → gets current rules if session active
3. Background polling in `StiraExtensionBridge` pushes `policy_update` whenever `active-policy.json` changes
4. `buildDNRRules(rules)` converts policy URL rules to Chrome DNR rules via `chrome.declarativeNetRequest.updateDynamicRules`
5. On `session_ended` or disconnect: `clearAllRules()` removes all dynamic DNR rules

### rule_builder.ts

`buildDNRRules(rules: ExtensionUrlRule[]): DNRRule[]` — each `action:"block"` rule becomes a Chrome DNR rule with `urlFilter: "*<pattern>*"`. Sequential IDs starting at 1.

### Dev installation

1. `npm run build` in `browser-extension/`
2. Chrome → `chrome://extensions` → Developer mode → Load unpacked → select `browser-extension/`
3. Extension ID must match `kceccioddldmaiodjklbpfmlmiogcbkb` for native messaging

---

## 7. IPC Protocol Reference

### Swift → Hermes (Unix socket, newline-delimited JSON)

| Message type | Fields | Sent when |
|---|---|---|
| `start_session` | `{type, policy: HermesTaskSpec}` | Session start |
| `stop_session` | `{type, session_id}` | Session end |
| `apply_exception` | `{type, bundle_id}` | Escape hatch granted |

### Hermes → Swift (same socket connection)

| Event type | Fields | Emitted when |
|---|---|---|
| `session_started` | `type, session_id, timestamp` | All skills started |
| `app_blocked` | `type, session_id, bundle_id, timestamp` | AppSuppressor fires |
| `focus_killed` | `type, session_id, bundle_id, timestamp` | FocusKiller fires |
| `app_opened` | `type, session_id, bundle_id, timestamp` | Any app activates |
| `session_ended` | `type, session_id, timestamp` | SessionController.stop() |
| `error` | `type, session_id, message, timestamp` | Exception during start |

### StiraExtensionBridge → Chrome extension (native messaging, 4-byte LE length prefix)

| Message type | Fields | When |
|---|---|---|
| `policy` | `{type, rules: ExtensionUrlRule[]}` | Response to `get_policy` |
| `policy_update` | `{type, rules: ExtensionUrlRule[]}` | `active-policy.json` modified |
| `session_ended` | `{type}` | `active-policy.json` deleted |

---

## 8. File System Paths (Runtime)

All under `~/Library/Application Support/Stira/`:

| Path | Written by | Read by | When |
|---|---|---|---|
| `hermes.sock` | Hermes (binds) | Swift (connects) | Session lifecycle |
| `active-policy.json` | PolicyStore | ExtensionBridge, Chrome ext | Session active |
| `hermes.log` | Hermes | Developer | Always |
| `sessions/<uuid>/audit.jsonl` | SessionManager | Developer | After each session |

---

## 9. Development Setup

```bash
# Prerequisites
brew install ollama
ollama pull qwen3:8b   # 5GB, one-time
cd hermes && pip install -e ".[macos,dev]"

# Run the app
cd stira-macos && swift run Stira

# Stop
Ctrl+C   # Hermes exits within 2s
# Kill lingering orphan if needed:
pkill -f stira.main

# Tests
cd stira-macos && swift test
cd hermes && pytest
cd browser-extension && npm test
```

On first launch, onboarding runs automatically: RAM check → Ollama check → model pull → Accessibility permission → complete.

---

## 10. Bugs Fixed in Development (Do Not Re-Introduce)

### 1. `startSession()` never launched Hermes (CRITICAL)
`SessionManager.startSession()` originally called `hermesSocket.startSession()` without first launching the Python subprocess. Fixed by adding `launchHermes()` at the top.

### 2. Escape hatch exceptions never reached Hermes (CRITICAL)
`handleEscapeHatchGrant()` updated `PolicyStore` but never sent `apply_exception` over the socket. Fixed by adding `hermesSocket.applyException(sessionId:bundleId:)`.

### 3. `hermesRoot()` walked too few directory levels (CRITICAL)
Original code walked 3 levels. `swift run` puts binary at `.build/debug/Stira` (needs 4). Arch-specific `.build/arm64-apple-macosx/debug/Stira` needs 5. Fixed: walk up to 6 levels.

### 4. Ollama JSON truncation (`num_predict: 2048`)
Caused LLM to stop mid-JSON. Fixed: `num_predict: -1` (unlimited).

### 5. `StiraPolicy` decode failure (memberwise init suppression)
Custom `init(from:)` in the struct body suppressed synthesized memberwise init. Fixed: moved to `extension StiraPolicy: Decodable`.

### 6. Socket ENOENT on new session (race condition)
`PolicyReceiver.stop()` called `os.unlink()`. New Hermes would bind the socket, then old Hermes's SIGTERM handler deleted it. Fixed: removed `os.unlink` from `stop()`.

### 7. `AppSuppressor` race on `blocked_bundle_ids`
Read on NSRunLoop thread, mutated from socket serve thread. Fixed: `threading.Lock`.

### 8. `AXIsProcessTrusted()` unreliable on macOS 26 debug builds
TCC ties grant to binary hash; every `swift run` invalidates it. Fixed: functional AX check via `AXUIElementCopyAttributeValue` + manual bypass button.

### 9. Toast pill invisible
`FocusKiller` brings Finder to front after every block. Stira's window goes behind Finder. Toast rendered but was hidden. Fixed: `NSApp.activate(ignoringOtherApps:true)` + `makeKeyAndOrderFront` in `triggerBlockedToast()`.

### 10. Hermes orphan after app exit
`NSRunLoop.run()` swallows SIGINT, so Hermes kept running and blocking apps after `swift run` Ctrl+C. Fixed: explicit SIGINT handler + parent PID watchdog thread.

### 11. `OllamaInstaller.launchOllamaApp()` only checked one path
Added fallback to Homebrew `ollama serve` for non-GUI installations.

### 12. Unix socket fd leak
`_serve_connection()` lacked `finally: conn.close()`. Fixed.

---

## 11. Pre-MVP Gaps (Ordered by Priority)

**Blocking a working demo:**

1. **pyobjc not bundled** — enforcement silently no-ops if pyobjc absent. Dev workaround: `pip install -e ".[macos]"` in `hermes/`. Distribution requires bundled Python + pyobjc or a PyInstaller binary.

2. **StiraExtensionBridge binary not in app bundle** — `hermesRoot()` handles the path (`Bundle.main.resourceURL + "hermes"`), but no Xcode copy build phase exists. Chrome extension is inert without it.

3. **Python not available on user machines** — `findPython()` checks Homebrew paths, but most users don't have Python. Distribution requires bundled runtime.

**UI/UX:**

4. **No menu bar icon** — app lives entirely in a floating window. Table-stakes for a focus tool.

5. **IntentInputView needs branding** — no wordmark, no example intent chips.

6. **No session summary** — no collapsed view of what's being blocked once session starts.

**Distribution:**

7. **No code signing** — debug builds break AX permission after every `swift run`. Production needs Developer ID signing + notarisation.

8. **Chrome extension not published** — ID `kceccioddldmaiodjklbpfmlmiogcbkb` only works if published to Chrome Web Store or installed as unpacked developer extension.

---

## 12. Architecture Constraints (Non-Negotiable)

1. **LLM never in enforcement hot path** — qwen3:8b fires ONCE at session start. Block decisions are policy lookups.
2. **Policy object is the single source of truth** — every component either produces or consumes `StiraPolicy`.
3. **`active-policy.json` is the only data channel to the browser extension** — `PolicyStore` is the sole writer. `StiraExtensionBridge` polls it. Do not add other IPC to Chrome.
4. **Hermes–Swift interface is a stable API surface** — the IPC message types are the contract. Hermes internals must not bleed into Swift.
5. **All enforcement is local** — no network calls during an active session.
6. **Standard escape hatch only for MVP** — other modes (`soft`, `strict`, `nuclear`) are defined in schema but not implemented.
7. **One permission ask** — Accessibility at first launch. Nothing else.
8. **No terminal visible to user** — Ollama install, model pull, and Hermes launch all happen inside the app's own UI.

---

## 13. Key Rules for AI Agents Working on This Repo

- Never add Co-Authored-By trailers to git commits
- Never run git with `--no-verify`
- Remote URL: `https://github.com/17ronith/Stira` (HTTPS via `gh` CLI, SSH requires passphrase)
- Active branch: `master`. Push target: `main`. Always push as `git push origin master:main`
- `num_predict` in Ollama call MUST be `-1`. Positive values truncate JSON.
- `format: "json"` in Ollama call MUST always be present.
- `os.unlink` MUST NOT be called in `PolicyReceiver.stop()` (Bug #6 above)
- `StiraPolicy: Decodable` MUST be in an extension, not the struct body (Bug #5 above)
- `NSApp.activate(ignoringOtherApps: true)` MUST be called before showing the toast (Bug #9 above)

---

## 14. Current Status (as of 2026-05-30)

Everything below is working end-to-end in `swift run`:

- Full session lifecycle: intent → Ollama → policy → Hermes → enforcement + events → toast + window focus
- App blocking via NSWorkspace, focus kill via Finder activation, Stira window brought to front
- URL blocking via `active-policy.json` → `StiraExtensionBridge` → Chrome DNR
- Escape hatch: 4-phase flow, exception reaches Hermes, `AppSuppressor.unblock()` called
- Session timer auto-ends session when `durationMinutes` expires
- Clean exit: Ctrl+C kills Hermes within 2s; crash/force-quit handled by watchdog
- Onboarding: RAM check, Ollama install, model pull with progress, AX permission with functional check
- Diagnostic prints in `HermesSocket.readEventLoop`, `SessionManager` event consumer, and `SessionStatusView.onChange` (can be stripped once stable)
