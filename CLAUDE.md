# Stira — Project Context for Claude Code / Codex

## What Stira Is

Stira is a local-first macOS desktop application (Windows to follow later) that reshapes a user's digital environment based on declared intent. The core problem it solves is the gap between what a user sits down to do and what their computer actually helps them do. Every app, notification, and browser tab is designed to pull attention away from the task at hand. Existing solutions like website blockers and timers are too blunt — they enforce restrictions without understanding why the user is at their computer in the first place.

Stira's approach is to make the digital environment context-aware at the level of user intent. The user expresses what they want to do in plain language. Stira interprets that intent and reshapes the environment to match it — surfacing what's relevant, suppressing what isn't, and holding the user to that intent for the session.

The competitive difference: every existing focus tool (Cold Turkey, Freedom, Apple Focus) is rule-based where the user manually authors the rules. Stira is rule-based where the AI authors the rules from a single natural language intent declaration. The moat is not enforcement — it's rule authorship.

---

## Architecture Overview

Stira has three components:

1. **Intent Engine** — interprets the user's declared intent via local LLM and produces a structured Policy object
2. **Hermes Agent (modified)** — acts as both the stateful reasoning harness and the macOS enforcement layer
3. **Browser Extension** — handles within-browser enforcement that the OS layer cannot reach

These three components are the complete stack. There is no cloud backend, no remote database, no telemetry.

---

## Component 1: Intent Engine

### How it works
The user types a natural language intent. The intent engine sends it to a local LLM (qwen3:8b via Ollama) with the StiraPolicy JSON schema and a structured prompt. The model returns a valid policy object using Ollama's constrained decoding — the `format` parameter enforces the schema at the token generation level, guaranteeing valid JSON every time. No post-hoc parsing, no markdown fences, no malformed output.

### Local LLM: qwen3:8b via Ollama
- **Model:** qwen3:8b
- **Runtime:** Ollama at localhost:11434
- **Why Qwen3:** Most stable structured output and tool calling of any model in its size class in 2026. Rarely hallucinates fields or drops parameters.
- **Memory footprint:** ~6GB at Q4 quantisation — comfortable on 16GB+ Macs
- **System requirement:** 16GB RAM minimum (stated clearly on download page)
- **Tokens/sec on M3 Pro:** 18-25 tok/s — fast enough for intent parsing at session start

### Bundling strategy
Ollama and qwen3:8b are bundled into the Stira installer. The user never sees a terminal. Onboarding:
1. Stira installer detects if Ollama is already installed — skips silently if so
2. If not, installs Ollama automatically
3. Pulls qwen3:8b in the background with a visible progress bar inside Stira's own UI
4. One-time 5GB download, clearly communicated on the download page before install

### Future upgrade path
Claude API replaces Ollama as the default intent engine post-MVP for faster responses and zero RAM requirement. The abstraction layer is built from day one so the backend is swappable without touching any other component. Local Ollama mode becomes an opt-in power user feature promoted to r/LocalLLaMA and r/selfhosted.

### The division of labour
- **Qwen3:8b** — stateless. Reads the intent, produces the policy object, stops. Has no memory of previous sessions.
- **Hermes** — stateful. Remembers everything across sessions. Feeds historical context back into each Qwen call to make the policy smarter over time.

### Output: The Policy Object
The intent engine's output is a structured policy object — the central data structure of the entire product. Every component either produces it or consumes it. The schema must be expressive enough to handle:

- App allow/block lists (block_listed or allow_listed mode)
- URL block rules with path-level exceptions
- Session duration
- Conditional exceptions (e.g. YouTube blocked except youtube.com/watch for lectures)
- Confidence score
- Escape hatch mode for the session
- Notification posture

Better intent parsing on a weak policy schema produces wrong automation faster — the schema is more important than model quality.

### MVP Architecture note
For MVP, intent parsing is a direct Ollama/Qwen3 call. The three-layer production pipeline (FastText → BGE-small-en → Claude API fallback) is post-MVP — it requires real-world intent data to train and adds build complexity before there are users.

---

## Component 2: Hermes Agent (Modified)

### The division of labour between Qwen and Hermes
This is the most important thing to understand about the architecture:

- **Qwen** reads intent + historical context → produces policy object → stops
- **Hermes** enforces the policy during the session + logs everything + remembers across sessions + feeds context back to Qwen next time

Qwen is the brain for one moment. Hermes is the memory and the hands for everything else.

### Why Hermes

Hermes Agent is an open-source autonomous agent framework built by Nous Research (MIT license). It was chosen for two reasons specific to Stira:

1. **Persistent learning**: Hermes maintains memory across sessions and automatically writes reusable skill documents when it solves problems. Over time Stira's enforcement learns a specific user's distraction patterns, intent expressions, and drift behaviours. On day one the policy for "coding session" is generic. On day 30 it reflects that this user always needs Figma open, drifts to YouTube within 40 minutes, and declares sessions that always run 3x longer than stated. Hermes feeds that history into every Qwen call as context — making the policy smarter without the user configuring anything.

2. **Native macOS computer control**: Hermes drives the Mac desktop in the background using macOS accessibility APIs — suppressing windows, monitoring app focus, injecting events — without moving the user's cursor, stealing keyboard focus, or switching Spaces. It posts synthesized events directly to target processes via SkyLight private SPIs and the accessibility SPI, not at the HID level.

### The full session loop
```
User types intent
    ↓
Hermes retrieves past session patterns for this user
    ↓
Qwen receives: intent + historical context from Hermes
    ↓
Qwen produces: policy object (smarter because of context)
    ↓
Hermes enforces that policy for the session
    ↓
Hermes logs every app switch, block, focus kill, escape hatch
    ↓
Hermes updates its memory
    ↓
Next session: repeat, but smarter
```

### Critical Architectural Principle
Stira must maintain a clean interface boundary with Hermes. Hermes is an active research project — it will change. Stira owns: session policy, permissions, audit logs, enforcement decisions, and UX. Hermes is the execution harness, not the product brain. The interface contract between Stira and Hermes must be treated as a stable API surface. Hermes internals must not bleed into Stira's product logic.

### How Hermes Must Be Modified

- **The input layer is removed entirely.** No chat interface, no messaging gateway, no CLI prompt. The user never knows Hermes is running.
- **The intent engine is wired directly to Hermes's task execution layer.** The policy object is passed programmatically via Unix domain socket. Hermes wakes, reads the policy, begins enforcing — no human message in the loop.
- **Enforcement is policy-driven, not LLM-driven at runtime.** The LLM fires once at intent declaration time. Enforcement is a lookup against the pre-computed policy — not an inference call on every trigger. The LLM must never be in the hot path of a block decision.
- **Required skills are pre-loaded and hardwired.** App suppression, window focus monitoring, session enforcement — baked in at build time. Every user gets a complete enforcement layer on day one.
- **Memory is scoped per user install.** Hermes's persistent memory is pointed at ~/Library/Application Support/Stira/hermes-memory/. Each install learns independently. No data leaves the machine.
- **Hermes runs invisibly as a background process.** No separate window, no visible interface.

### MVP Hermes Scope
Three enforcement capabilities only:
1. Block a named app from foregrounding
2. Kill focus on a named app if it comes to front
3. Monitor and log what apps the user opens during the session

No computer control beyond these three. No complex skill library. Learning layer ships but is not load-bearing for MVP — it accumulates data and becomes load-bearing post-MVP.

### IPC: Unix Domain Socket
Hermes is Python. The native app is Swift. XPC is elegant within Swift but requires C bindings on the Python side — too much boilerplate. Use a Unix domain socket with newline-delimited JSON instead. Same process isolation, simpler implementation, works natively across both languages.

```
Stira UI → socket → Hermes: {"type": "start_session", "policy": {...}}
Hermes → socket → Stira UI: {"type": "app_blocked", "bundle_id": "com.twitter.twitter", "timestamp": "..."}
Stira UI → socket → Hermes: {"type": "stop_session"}
```

### macOS Permissions Note
macOS requires the user to explicitly grant Accessibility access in System Preferences before Hermes can use background control APIs. This is the only permission asked for at first launch. Do not ask for Full Disk Access, Chrome extension permissions, or anything else before the user has seen the core loop work once.

### Platform Risk
Apple hostility to Accessibility APIs is the primary platform-level existential risk. macOS sandboxing improvements routinely break third-party automation. Abstract all Accessibility API calls behind a single EnforcementLayer interface so they can be swapped if Apple changes behaviour.

---

## Component 3: Browser Extension

The browser extension handles enforcement for anything inside a browser. Hermes and macOS accessibility APIs see the browser as a single process — they cannot reach inside a webpage to suppress the Instagram DMs panel while leaving the feed visible.

### Within-browser enforcement layers

**Layer 1 — URL Rules (primary, MVP)**
Uses `declarativeNetRequest` to block entire routes before they load. Compiles into the browser's request interception pipeline, fires before the page loads. Fast, reliable, zero-maintenance. This is the only browser extension layer in MVP.

Supports path-level exceptions: youtube.com blocked but youtube.com/watch allowed when intent is educational. This is the YouTube lecture use case — the URL path is the discriminator, not the video content. Content-level classification (blocking gaming videos while allowing lectures on the same URL pattern) is not in scope.

**Layer 2 — DOM Manipulation (secondary, post-MVP)**
Uses MutationObserver with ARIA attributes and data-testid selectors. More granular but requires periodic maintenance — large web apps use obfuscated class names that change on redeploy. Claude Code fixes selector breakage quickly when it happens.

**Layer 3 — Vision Fallback (tertiary, post-MVP)**
Takes a screenshot, identifies target elements visually, acts on coordinates. Immune to selector rot. Slower but resilient. Fires automatically when Layer 2 selectors fail.

### Within-app native filtering
Blocking a specific WhatsApp DM thread while leaving the rest of WhatsApp open is not in scope for MVP or near post-MVP. Native app UI manipulation via Accessibility APIs is too brittle and app-version-dependent. Post-MVP solution when needed: contact allowlisting at the notification level via macOS Focus Mode contact filtering — not UI manipulation.

### Browser scope
Chrome only for MVP. Safari post-MVP.

### Extension Onboarding
Surface the browser extension as a "want more granular control?" prompt after the user has seen the core native enforcement loop work. Not a first-run requirement.

---

## The Escape Hatch Problem

The hardest design problem in Stira is the override mechanism. It is a design problem, not a technical one. The override UX is the product's personality — every override attempt is a conversation between Stira and the user. Language must be neutral, curious, non-judgmental: "You asked to stay in writing mode — open Twitter for how long?" Preachy or shaming language loses user trust permanently. Every escape attempt is training data for Hermes — it tells Stira where the policy was wrong or where the user was genuinely impulsive.

### Four Escape Hatch Modes
- **Soft**: Instant override, Stira asks what changed, updates future policies
- **Standard**: 30–90 second delay, typed reason required (minimum 20 characters), scoped exception only — not global disable. **MVP implements this mode only.**
- **Strict**: Delayed unlock plus scoped exception only, no global disable
- **Nuclear**: Pre-committed lock, opt-in only before session starts

The mode is set per session as part of the policy object.

---

## MVP Scope

### What's In
- Ollama + qwen3:8b bundled in installer for local intent parsing
- Policy schema — minimal but expressive, supports conditional exceptions from day one
- Hermes modified to three core enforcement actions
- Browser extension — URL rules only via declarativeNetRequest, with path-level exceptions
- Minimal UI — one text field, one button, session status indicator
- Single permission ask at onboarding — Accessibility only
- Standard escape hatch mode only (30-second delay, typed reason, scoped exception)
- Setup flow that installs Ollama and pulls qwen3:8b with progress bar — no terminal visible to user

### What's Out (post-MVP)
- Claude API as default intent engine (replaces Ollama post-MVP for speed and zero RAM requirement)
- FastText and BGE-small-en local pipeline
- DOM manipulation and vision fallback in browser extension
- Within-app native filtering
- All escape hatch modes except Standard
- Paddle integration and pricing infrastructure
- Analytics and session reporting
- Settings screen or manual policy editing
- Safari support
- Notification suppression automation

### The 10-Second Test
MVP acceptance criterion: user declares intent → environment visibly changes → within 10 seconds → with one permission ask. If this loop requires configuration before it works, the MVP has failed.

### MVP Build Order
1. Policy schema — define the JSON structure. Everything depends on this.
2. Ollama integration — wire qwen3:8b with constrained JSON output against the schema. Test with 10+ varied intents before touching anything else.
3. Hermes modification — strip to three core actions, wire policy object in via Unix socket.
4. Browser extension — URL rules driven by the same policy object.
5. UI — text field, session status, escape hatch countdown. Build last.
6. Installer + setup flow — Ollama bundling, model pull progress bar, Accessibility permission onboarding. Polish disproportionately — this is the first thing every user sees.

---

## Business Model

- **Distribution**: Direct download, no app store
- **Pricing**: One-time purchase with optional subscription
- **Trial**: 14-day free trial, no card required
- **Free tier**: Permanent, scoped to one full focus session per day
- **Pricing adjustment**: PPP-based via Paddle for emerging market accessibility
- **System requirement**: 16GB RAM minimum — stated on download page
- **GTM**: Hacker News technical writeup, r/macapps, r/LocalLLaMA, r/selfhosted. SEO targeting "Cold Turkey alternative for Mac." Launch asset is a 60-second screen recording of the 10-second loop working. Instagram is the wrong channel for this product.

---

## What Was Evaluated and Rejected

- **Win32 controller**: Dropped when the decision was made to go Mac-first. Hermes's native macOS computer control makes a separate enforcement module unnecessary.
- **OpenHuman**: Rejected — achieves context by requesting broad continuous OAuth access to email, calendar, code repositories. Directly contradicts local-first positioning.
- **NemoClaw**: Rejected — sandboxing relies on Linux kernel primitives that do not exist on macOS.
- **OpenClaw**: Rejected — no persistent learning loop, less mature macOS computer control than Hermes.
- **OpenHands**: Rejected — software engineering coding agent, not relevant.
- **XPC for IPC**: Rejected in favour of Unix domain socket — XPC requires C bindings on the Python/Hermes side, too much boilerplate for the same result.
- **Claude API as MVP intent engine**: Rejected for launch — requires API key, adds network dependency, weakens local-first story. Kept as the post-MVP upgrade path.
- **Qwen2.5:7b**: Superseded by qwen3:8b — Qwen3 has more stable structured output and tool calling.

---

## Key Constraints

1. Hermes must run as an invisible background process — no user-facing interface of its own
2. The policy object is the central data structure — every component either produces it or consumes it. Get the schema right before building anything else.
3. The LLM must never be in the hot path of enforcement decisions. Reasoning fires once at intent declaration. Enforcement is a policy lookup.
4. Ollama's `format` parameter must be used for constrained JSON decoding — do not rely on prompt-based JSON instruction alone, it fails unpredictably.
5. The Stira–Hermes interface boundary is a stable API surface. Stira's product logic must not bleed into Hermes internals. Pin Hermes to a specific commit hash.
6. IPC between Swift UI and Hermes Python subprocess is a Unix domain socket with newline-delimited JSON.
7. All enforcement is local — no network calls during an active session.
8. Memory and learning scoped to ~/Library/Application Support/Stira/ — nothing leaves the machine.
9. The browser extension and Hermes enforcement layer are separate concerns — do not conflate them.
10. Standard escape hatch only for MVP: 30-second delay, 20-character minimum reason, scoped exception only.
11. Progressive permission asks — Accessibility permission only at first launch.
12. The 10-second test is the MVP acceptance criterion.
13. The installer must never show a terminal to the user — Ollama install and model pull happen inside Stira's own UI with a progress bar.
14. System requirement is 8GB RAM minimum — enforce this check at launch and surface a clear error if not met.


## MVP Build

You are the sole engineer building Stira MVP. Read the attached context file completely before writing a single line of code. Every architectural decision has already been made — do not relitigate them.
The MVP consists of exactly these components:

A local intent engine that takes natural language input and produces a StiraPolicy JSON object using qwen3:8b via Ollama with constrained JSON decoding
A modified Hermes Agent running as an invisible background subprocess with exactly three hardwired enforcement skills: app suppression, focus killing, and app monitoring — receiving policy via Unix domain socket and emitting audit events back the same way
A Chrome browser extension that receives the URL rules from the active policy via native messaging and applies them using declarativeNetRequest
A Swift/SwiftUI native macOS app with a single intent input field, session status display, and Standard-mode escape hatch UX
A Policy Store that holds the active session policy and makes it readable by all enforcement components
A Session Manager that orchestrates the full session lifecycle
An installer and first-run flow that handles Ollama installation, qwen3:8b model pull with progress bar, and Accessibility permission onboarding — no terminal visible to the user at any point

The MVP acceptance criterion is the 10-second test: user declares intent, environment visibly changes, within 10 seconds, with one permission ask.
Before writing any code, produce the policy schema first and wait for my approval. Then build one component at a time and wait for my sign-off before proceeding to the next.

---

## Implementation Notes — Bugs Found and Fixed in Development

These are runtime issues discovered during the first real end-to-end run. Document them so future sessions don't repeat the investigation.

### 1. Hermes subprocess was never launched (CRITICAL)
`SessionManager.startSession()` called `hermesSocket.startSession()` directly without first launching the Hermes Python subprocess. Fixed by adding `launchHermes()` at the top of `startSession()`, before the 0.5s sleep and the Ollama call.

### 2. Escape hatch exceptions never reached Hermes (CRITICAL)
`handleEscapeHatchGrant()` in `SessionManager` updated the in-Swift `PolicyStore` via `applyException()` but never sent an `apply_exception` message over the Unix socket to Hermes. Hermes's `AppSuppressor` kept the bundle ID blocked. Fixed by adding `apply_exception` as a new IPC message type, wiring it through `policy_receiver.py` → `session_controller.py` → `app_suppressor.unblock()`.

### 3. `hermesRoot()` walked too few directory levels (CRITICAL for `swift run`)
The original code walked 3 levels up from the executable. When running `swift run`, the binary lives at `stira-macos/.build/debug/Stira` — 3 levels up lands at `stira-macos/`, not the project root where `hermes/` lives. `swift build` arch-specific paths (`.build/arm64-apple-macosx/debug/Stira`) need 5 levels. Fixed: iterate up to 6 levels and return on the first ancestor that contains a `hermes/` subdirectory.

### 4. Native messaging manifest installed at dev path instead of real binary path (HIGH)
`OnboardingCoordinator.installNativeMessagingManifest()` was not present — it was added during the fix cycle. The manifest is now written at the end of onboarding, pointing to the actual `StiraExtensionBridge` binary found alongside the running executable. Non-fatal if the bridge binary isn't present (development without the extension).

### 5. `AppSuppressor` had a race condition on `blocked_bundle_ids` (HIGH)
The list was read on the NSRunLoop/main thread (from `appDidActivate_` notifications) and mutated from the socket serve thread (on `apply_exception` and `unblock()`). Fixed by adding `threading.Lock` protecting all reads and writes.

### 6. `AXIsProcessTrusted()` unreliable on macOS 26 for debug builds (PLATFORM BUG)
On macOS 26 Tahoe (Darwin 25), TCC ties accessibility permission entries to the binary's code hash at grant time. Every `swift build` / `swift run` produces a new ad-hoc signed binary with a different hash, making the old TCC entry invalid even while the System Settings toggle shows ON. `AXIsProcessTrusted()` returns false despite the toggle being enabled.
**Workaround implemented:**
- Call `AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true])` on first entering the permission step — this shows the system dialog and registers the *current* binary with TCC.
- Add `DistributedNotificationCenter` listener for `com.apple.accessibility.api` for immediate auto-detection when it works.
- Add a "I've granted permission — continue" button that calls `permissionTrigger?.finish()` to force-proceed without re-checking `AXIsProcessTrusted()`, trusting the user's manual confirmation.
- **For production builds** (signed with a stable Developer ID), `AXIsProcessTrusted()` works correctly. This issue only affects debug builds.

### 7. `OllamaInstaller.launchOllamaApp()` only handled the `.app` bundle path
Added fallback: if `~/Applications/Ollama.app` is not found, try `/opt/homebrew/bin/ollama serve` and `/usr/local/bin/ollama serve` as a subprocess. Required for developers who installed Ollama via Homebrew without the GUI app.

### 8. Unix socket connection file descriptor leak
`policy_receiver._serve_connection()` and the custom `_serve_connection_with_emitter()` in `main.py` both lacked `finally: conn.close()`. Fixed with `try/finally` blocks.

### 9. Dead code — PolicySchema.schemaJSON and intent-engine Python package
`stira-macos/Sources/Stira/Models/PolicySchema.swift` contained a static `schemaJSON` string that was never referenced at runtime (Ollama constrained decoding is driven by the `StiraPolicy` Codable schema directly). The `hermes/intent-engine/` Python prototype directory was never git-tracked. Both removed.

---

## Hermes Python Dependencies

Hermes uses `pyobjc` for all macOS API calls (NSWorkspace, NSRunningApplication). This package is **not installed by default** — it must be present for `AppSuppressor`, `AppMonitor`, and `FocusKiller` to function.

Install for development:
```bash
cd hermes && pip install -e ".[macos,dev]"
```

For the installer/distribution build, Python and pyobjc must either be bundled alongside the app or installed automatically as part of the setup flow. See Pre-MVP Gaps below.

The three skills gracefully degrade if pyobjc is absent (log warnings, no-op enforcement), which is correct for CI but wrong for production.

---

## Enforcement Does Not Require Explicit Accessibility Permission

Contrary to what the CLAUDE.md architecture section implies, none of the three MVP enforcement skills require macOS Accessibility permission:
- `AppSuppressor` — uses `NSWorkspace.didActivateApplicationNotification` and `NSRunningApplication.hide()`. No AX required.
- `FocusKiller` — activates Finder via `NSWorkspace` + `NSRunningApplication.activateWithOptions_()`. No AX required.
- `AppMonitor` — listens to `NSWorkspace` app launch notifications. No AX required.

The Accessibility permission screen in onboarding is correct to show (it will be needed post-MVP when deeper window control is added), but the app will function without it in the current MVP scope. The onboarding screen is therefore informational rather than a hard gate — which is why the manual "I've granted it" bypass is safe.

---

## Pre-MVP Gaps

Ordered by priority. Items marked [BLOCKING] will prevent a working demo.

### Functional Gaps

1. **[BLOCKING] pyobjc not bundled or auto-installed** — Hermes's three enforcement skills silently no-op if `pyobjc` is missing. For a demo, the developer must manually run `pip install -e ".[macos]"` in `hermes/`. For distribution, this must be automated in the setup flow or bundled.

2. **[BLOCKING] Session timer not enforced** — `session_duration_seconds` is included in the `HermesTaskSpec` sent to Hermes, but nothing auto-ends the session when that duration expires. `SessionStatusView` shows elapsed time but has no countdown or auto-stop. Either Hermes needs a timer skill or Swift's `SessionManager` needs to call `endSession()` after the policy duration.

3. **[BLOCKING] StiraExtensionBridge binary not built or bundled** — The native messaging manifest correctly points to `StiraExtensionBridge` beside the main executable, but `StiraExtensionBridge` is a separate build target. It needs to be built and present for the browser extension to receive policies. Without it the Chrome extension is inert.

4. **Python not available on user machines** — `findPython()` checks Homebrew paths and `/usr/bin/python3`. Most users don't have Python installed. Distribution requires either bundling a Python runtime in `Resources/` or using a pre-built self-contained Hermes binary (e.g. via PyInstaller).

5. **Hermes crash recovery** — No watchdog or restart logic. If Hermes crashes mid-session, the Swift app remains in `.active` state indefinitely with a dead socket. Needs a `Process.terminationHandler` that clears state or restarts.

6. **`findPython()` returns `/usr/bin/python3` stub on macOS** — The system path on macOS points to an Xcode command-line tools stub that prompts for installation rather than running Python. Current code added `fileExists` check, but `fileExists` returns true for the stub. Should validate by running `python3 --version` or checking for a real site-packages.

### UI/UX Gaps

7. **IntentInputView is bare** — No branding, no example intents, no visual hierarchy. At minimum needs: app icon/wordmark, 2–3 example intent chips ("focus on coding", "write without distractions", "deep reading"), and a subtle animation on submission.

8. **SessionStatusView lacks remaining time** — Shows elapsed time but the policy has a `durationMinutes`. Should show "X minutes remaining" prominently and transition to a warning state in the last 5 minutes.

9. **No session intent summary** — Once a session starts, the user has no way to see what apps/URLs were blocked. The session view should show the policy intent label and a collapsed list of what's being blocked.

10. **Onboarding needs visual polish** — Steps feel disconnected. A persistent progress indicator (step 1/4, 2/4…) would help. The model download view already has a progress bar; the permission and Ollama steps feel different.

11. **No menu bar icon** — The app lives in a regular window. For a focus tool, a menu bar presence (status icon showing session active/idle) is table-stakes UX. The main window can remain but the menu bar should reflect session state.

12. **Escape hatch "I need a break" trigger is wrong** — Currently uses `lastHermesEvent?.bundleId` as the exception target, which is the last *blocked* app. This means clicking "I need a break" generically targets whatever was blocked last, not what the user is actually trying to open. Should present a picker or text field for the target app.

### Distribution & Signing

13. **No code signing configuration** — Debug builds break AX permission on every rebuild (see §Implementation Notes #6). Production distribution requires Developer ID signing, which also enables Gatekeeper and notarisation. The Xcode project needs a signing configuration.

14. **Hermes not bundled in app Resources** — For distribution, `hermes/` must be embedded in `Stira.app/Contents/Resources/hermes/`. `hermesRoot()` already handles this via the `Bundle.main.resourceURL` path, but the Xcode build phase to copy the directory doesn't exist yet.

15. **Chrome extension not published** — The extension ID `kceccioddldmaiodjklbpfmlmiogcbkb` is hardcoded. This is valid only if the extension is published to the Chrome Web Store under that ID, or installed as an unpacked developer extension. For distribution, the extension needs to be published and the ID confirmed.

