# Stira

Stira is a local-first macOS focus app that reshapes your digital environment based on declared intent. You tell it what you're working on in plain English — it figures out what to block.

Unlike Cold Turkey or Freedom, Stira doesn't ask you to manually configure rules. It reads your intent and generates the policy automatically using a local LLM.

**Current state:** MVP development build. Core enforcement loop works end-to-end. Not yet packaged for distribution — requires manual setup.

---

## How it works

1. You type what you're working on ("deep work session on this feature", "writing without distractions")
2. Stira sends the intent to `qwen3:8b` running locally via Ollama
3. The model returns a structured policy — which apps to block, which URLs to block, session duration
4. A Python subprocess (Hermes) begins enforcing: hiding blocked apps when they come to the foreground
5. The browser extension applies URL block rules via Chrome's `declarativeNetRequest`

Everything runs locally. No cloud calls during a session.

---

## Requirements

- macOS 13 or later (tested on macOS 15/26)
- 16 GB RAM (qwen3:8b requires ~6 GB)
- [Ollama](https://ollama.com) with the `qwen3:8b` model
- Python 3.10+ with `pyobjc` (Homebrew Python recommended)
- Xcode 16+ with Swift Package Manager
- Google Chrome (for browser enforcement)

---

## Setup

### 1. Install Ollama and pull the model

```bash
# Install Ollama from https://ollama.com, then:
ollama pull qwen3:8b
```

Verify it works:
```bash
ollama run qwen3:8b "hello"
```

### 2. Install Python dependencies

```bash
cd hermes
pip install -e ".[macos,dev]"
```

This installs `pyobjc` and other dependencies Hermes needs to interact with macOS APIs.

> **Note:** Use Homebrew Python (`/opt/homebrew/bin/python3`), not the macOS system stub at `/usr/bin/python3`.

### 3. Build and run the Swift app

```bash
cd stira-macos
swift run
```

The app opens a window. On first launch it walks through:
- Checking Ollama is running
- Requesting Accessibility permission (needed for future enforcement features; current MVP works without it)

### 4. Load the browser extension (optional)

1. Open Chrome → `chrome://extensions`
2. Enable **Developer mode**
3. Click **Load unpacked** → select the `browser-extension/` directory

The extension receives the active policy from the native messaging bridge and blocks URLs using Chrome's declarative rules.

---

## Project structure

```
stira-macos/          Swift/SwiftUI macOS app
  Sources/Stira/
    App/              App entry point, window setup
    Models/           StiraPolicy schema (Codable)
    SessionManager/   Session lifecycle orchestration
    HermesSocket/     Unix socket client (Swift ↔ Python IPC)
    PolicyStore/      Active policy persistence
    Onboarding/       First-run flow (Ollama check, permissions)
    UI/               Session status, escape hatch, glass components
    ExtensionBridge/  Native messaging bridge for Chrome extension

hermes/               Python enforcement subprocess
  stira/
    main.py           Entry point, socket server, SIGTERM handler
    policy_receiver.py  Unix socket server, message dispatch
    session_controller.py  Session lifecycle, skill coordination
    event_emitter.py  Writes JSON events back to Swift over socket
    skills/
      app_suppressor.py   Hides blocked apps when they foreground
      focus_killer.py     Activates Finder to kill app focus
      app_monitor.py      Logs app switches during session

browser-extension/    Chrome extension
  manifest.json
  background.js       Receives policy, applies declarativeNetRequest rules

docs/                 Architecture docs and implementation plans
```

---

## Architecture

The three components communicate through shared data:

```
Swift app  ──socket──▶  Hermes (Python)
    │                       │
    │                   enforces policy
    │                   emits events back
    │
    └──active-policy.json──▶  Chrome extension
                               (via native messaging bridge)
```

**IPC:** Unix domain socket at `~/Library/Application Support/Stira/hermes.sock`. Newline-delimited JSON in both directions.

**Policy object:** Central data structure produced by Ollama/Qwen3 at session start. Every enforcement component consumes it. Schema defined in `stira-macos/Sources/Stira/Models/StiraPolicy.swift`.

**LLM is not in the enforcement hot path.** Reasoning fires once at session start. Enforcement is a policy lookup — no inference calls when an app is blocked.

---

## Development notes

### macOS permission for debug builds

On macOS 15+, Accessibility permission is tied to the binary's code hash. Every `swift run` produces a new binary, invalidating the previous TCC entry. If the accessibility toggle appears ON but `AXIsProcessTrusted()` returns false, revoke the permission in System Settings → Privacy & Security → Accessibility and re-grant it.

Current enforcement (app hiding, focus killing) works without Accessibility permission. This only matters for post-MVP deeper window control.

### Hermes subprocess lifecycle

The Swift app launches Hermes as a subprocess on session start and terminates it on session end. On app restart, any orphaned Hermes processes from the previous run are killed before launching a new one.

Hermes logs to `~/Library/Application Support/Stira/hermes.log`.

### Known limitations (current dev build)

- Python must be manually installed (not bundled)
- No code signing — Gatekeeper will block distribution builds
- Browser extension must be sideloaded; not published to Chrome Web Store
- No menu bar icon
- No session history or reporting UI

---

## Running tests

```bash
# Hermes Python tests
cd hermes
pytest

# Swift build check
cd stira-macos
swift build
```

---

## License

MIT
