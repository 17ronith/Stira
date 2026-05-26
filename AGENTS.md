# Stira — Project Context for Codex

## What Stira Is

Stira is a local-first macOS desktop application (Windows to follow later) that reshapes a user's digital environment based on declared intent. The core problem it solves is the gap between what a user sits down to do and what their computer actually helps them do. Every app, notification, and browser tab is designed to pull attention away from the task at hand. Existing solutions like website blockers and timers are too blunt — they enforce restrictions without understanding why the user is at their computer in the first place.

Stira's approach is to make the digital environment context-aware at the level of user intent. The user expresses what they want to do in plain language. Stira interprets that intent and reshapes the environment to match it — surfacing what's relevant, suppressing what isn't, and holding the user to that intent for the session.

---

## Architecture Overview

Stira has three components:

1. **Intent Engine** — interprets the user's declared intent and produces a structured enforcement policy
2. **Hermes Agent (modified)** — acts as both the reasoning harness and the macOS enforcement layer
3. **Browser Extension** — handles within-browser enforcement that the OS layer cannot reach

These three components are the complete stack. There is no cloud backend, no remote database, no telemetry.

---

## Component 1: Intent Engine

### Production Architecture (post-MVP)
The intent engine is a three-layer local NLP pipeline that runs entirely on the user's machine.

- **Layer 1 — FastText**: Fast, lightweight classifier for common, well-defined intents. Handles the majority of cases with minimal latency.
- **Layer 2 — BGE-small-en**: Semantic embedding model for fuzzier, more nuanced expressions of intent that FastText cannot confidently resolve.
- **Layer 3 — Codex API fallback**: Fires only for edge cases neither local model can handle. Users can disable this entirely via a toggle, keeping the product fully local. When the API fallback fires, Stira makes the network boundary explicit in the UI — users always know when data has left their machine.

### MVP Architecture
For MVP, replace the three-layer pipeline with a direct Ollama call using qwen3:8b at localhost:11434. FastText and BGE-small-en are latency and cost optimisations for production — they require real-world intent data to train meaningfully and add build complexity before there are users. The Ollama `format` parameter provides constrained JSON decoding — the model cannot produce output that violates the schema. The abstraction layer is built from day one so the three-layer pipeline (or Claude API post-MVP) can be dropped in later without touching the rest of the stack. Do NOT use the Codex API or Claude API for MVP intent parsing — the product is local-first and must work offline.

### Output: The Policy Object
The intent engine's output is a structured policy object — the central data structure of the entire product. This is the most important technical design decision in Stira. The policy schema must be expressive enough to handle:

- App allow/block lists
- URL block rules
- Session duration
- Conditional exceptions (e.g. YouTube blocked except youtube.com/watch — for lectures)
- Confidence score from the intent engine
- Escape hatch mode for the session
- Notification posture

The policy object is passed directly to Hermes's internal task execution layer. No human message is involved in this handoff. Better intent parsing on a weak policy schema produces wrong automation faster — the schema is more important than classifier accuracy.

---

## Component 2: Hermes Agent (Modified)

### Why Hermes

Hermes Agent is an open-source autonomous agent framework built by Nous Research (MIT license). It was chosen for two reasons specific to Stira:

1. **Persistent learning**: Hermes maintains memory across sessions and automatically writes reusable skill documents when it solves problems. Over time, Stira's enforcement learns a specific user's distraction patterns, intent expressions, and drift behaviours. An enforcement layer that knows the user becomes progressively harder to game — central to Stira's value as a commitment device.

2. **Native macOS computer control**: Hermes drives the Mac desktop in the background using macOS accessibility APIs — suppressing windows, monitoring app focus, injecting events — without moving the user's cursor, stealing keyboard focus, or switching Spaces. It posts synthesized events directly to target processes via SkyLight private SPIs and the accessibility SPI, not at the HID level. Hermes is both the reasoning layer and the enforcement layer. No separate custom OS module is needed.

### Critical Architectural Principle
Stira must maintain a clean interface boundary with Hermes. Hermes is an active research project — it will change. Stira owns: session policy, permissions, audit logs, enforcement decisions, and UX. Hermes is the execution harness, not the product brain. The interface contract between Stira and Hermes must be treated as a stable API surface, not an internal implementation detail. Hermes internals must not bleed into Stira's product logic.

### How Hermes Must Be Modified

- **The input layer is removed entirely.** No chat interface, no messaging gateway, no CLI prompt. The user never knows Hermes is running.
- **The intent engine is wired directly to Hermes's task execution layer.** The policy object is passed programmatically. Hermes wakes, reads the policy, and begins enforcing — no human message in the loop.
- **Enforcement is policy-driven, not LLM-driven at runtime.** The LLM fires once at intent declaration time. Enforcement is a lookup against the pre-computed policy — not an inference call on every trigger. The LLM must not be in the hot path of every block decision.
- **Required skills are pre-loaded and hardwired.** App suppression, window focus monitoring, session enforcement — baked in at build time. Every user gets a complete enforcement layer on day one.
- **Memory is scoped per user install.** Hermes's persistent memory is pointed at a local directory on the user's machine. Each install learns independently. No data leaves the machine.
- **Hermes runs invisibly as a background process.** No separate window, no visible interface.

### MVP Hermes Scope
Three enforcement capabilities only:
1. Block a named app from foregrounding
2. Kill focus on a named app if it comes to front
3. Monitor and log what apps the user opens during the session

No computer control beyond these three. No complex skill library. Learning layer ships but is not load-bearing for MVP.

### macOS Permissions Note
macOS requires the user to explicitly grant Accessibility access in System Preferences before Hermes can use background control APIs. This is the only permission asked for at first launch. Do not ask for Full Disk Access, Chrome extension permissions, or a Codex API key before the user has seen the core loop work once. Earn the right to ask for more after demonstrating value.

### Platform Risk
Apple hostility to Accessibility APIs is the primary platform-level existential risk. macOS sandboxing improvements routinely break third-party automation. Stira needs a contingency plan for the day Apple tightens these APIs.

---

## Component 3: Browser Extension

The browser extension handles enforcement for anything inside a browser. Hermes and macOS accessibility APIs see the browser as a single process — they cannot reach inside a webpage to suppress the Instagram DMs panel while leaving the feed visible.

Enforcement works in three layers of descending stability:

### Layer 1 — URL Rules (primary, MVP)
Uses `declarativeNetRequest` to block entire routes before they load. Fast, reliable, zero-maintenance. This is the only browser extension layer in MVP.

### Layer 2 — DOM Manipulation (secondary, post-MVP)
Uses `MutationObserver` with ARIA attributes and `data-testid` selectors to manipulate pages that have loaded. More granular but requires periodic maintenance due to obfuscated class names that change on redeploy.

### Layer 3 — Vision Fallback (tertiary, post-MVP)
Takes a screenshot, identifies target elements visually, acts on coordinates. Immune to selector rot. Slower but resilient. Fires automatically when Layer 2 selectors fail.

### Extension Onboarding
Surface the browser extension as a "want more granular control?" prompt after the user has seen the core native enforcement loop work. Do not make it a first-run requirement.

---

## The Escape Hatch Problem

The hardest design problem in Stira is the override mechanism. It is a design problem, not a technical one. The override UX is the product's personality — every override attempt is a conversation between Stira and the user. Language must be neutral, curious, and non-judgmental ("You asked to stay in writing mode — open Twitter for how long?"). Preachy or shaming language loses user trust permanently regardless of enforcement quality. Every escape attempt is training data — it tells Stira where the policy was wrong or where the user was genuinely impulsive.

### Four Escape Hatch Modes
- **Soft**: Instant override, Stira asks what changed, updates future policies. For when the policy was genuinely wrong.
- **Standard**: 30–90 second delay, typed reason required, scoped exception only (not global disable). **MVP implements this mode only.**
- **Strict**: Delayed unlock plus scoped exception only, no global disable.
- **Nuclear**: Pre-committed lock, opt-in only before session starts.

The mode is set per session as part of the policy object.

---

## MVP Scope

### What's In
- Direct Codex API call for intent parsing
- Policy schema — minimal but expressive, must support conditional exceptions from day one
- Hermes modified to three core enforcement actions
- Browser extension — URL rules only
- Minimal UI — one text field, one button, session status indicator
- Single permission ask at onboarding — Accessibility only
- Standard escape hatch mode only

### What's Out (post-MVP)
- FastText and BGE-small-en local pipeline
- DOM manipulation and vision fallback in browser extension
- Hermes session learning as a load-bearing feature
- All escape hatch modes except Standard
- Paddle integration and pricing infrastructure
- Analytics and session reporting
- Settings screen or manual policy editing

### The 10-Second Test
The MVP acceptance criterion: user declares intent → environment visibly changes → within 10 seconds → with one permission ask. If this loop requires any configuration before it works, the MVP has failed its core premise.

### MVP Build Order
1. Policy schema — define the JSON structure first. Everything depends on this.
2. Intent → policy — Codex API call, test extensively with varied inputs before touching anything else.
3. Hermes modification — strip to three core actions, wire policy object in.
4. Browser extension — URL rules driven by the same policy object.
5. UI — text field and session status. Build last.
6. First-run flow — single permission ask and onboarding. Polish disproportionately.

---

## Business Model

- **Distribution**: Direct download, no app store
- **Pricing**: One-time purchase with optional subscription
- **Trial**: 14-day free trial, no card required
- **Free tier**: Permanent, scoped to one full focus session per day
- **Pricing adjustment**: PPP-based via Paddle for emerging market accessibility
- **GTM**: Hacker News technical writeup, r/macapps, r/LocalLLaMA, r/selfhosted. SEO targeting "Cold Turkey alternative for Mac." Launch asset is a 60-second screen recording of the 10-second loop working — not a landing page. Instagram is the wrong channel for this product.



## Key Constraints for Codex

1. Hermes must run as an invisible background process — no user-facing interface of its own
2. The policy object is the central data structure — every component either produces it or consumes it. Get the schema right before building anything else.
3. The LLM must not be in the hot path of enforcement decisions. Reasoning fires once at intent declaration. Enforcement is a policy lookup.
4. The Stira–Hermes interface boundary must be treated as a stable API surface. Stira's product logic must not bleed into Hermes internals.
5. All enforcement must be local by default — Codex API fallback is opt-in and clearly signalled in the UI
6. Memory and learning must be scoped to the individual user's local machine
7. The browser extension and Hermes enforcement layer are separate concerns — do not conflate them
8. The escape hatch is a design problem — Standard mode only for MVP: 30-second delay, typed reason, scoped exception only
9. Progressive permission asks — Accessibility permission only at first launch
10. The 10-second test is the MVP acceptance criterion