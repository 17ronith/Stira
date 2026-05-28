// SessionManager.swift
// Orchestrates the full session lifecycle: intent -> Ollama -> Hermes -> extension bridge.

import Foundation
import SwiftUI

@MainActor
final class SessionManager: ObservableObject {
    enum SessionState: Equatable {
        case idle
        case starting
        case active
        case escapeHatch
        case ending
    }

    @Published var state: SessionState = .idle
    @Published var errorMessage: String?
    @Published var sessionStartTime: Date?
    @Published var lastHermesEvent: HermesEvent?

    let policyStore = PolicyStore()
    let escapeHatchController = EscapeHatchController()

    private var hermesSocket = HermesSocket()
    private var auditLog: [HermesEvent] = []
    private var hermesProcess: Process?

    // MARK: - Init

    init() {
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.hermesProcess?.terminate()
        }
    }

    // MARK: - Session Lifecycle

    func startSession(rawIntent: String) async {
        let trimmed = rawIntent.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            errorMessage = "Please describe what you want to focus on."
            return
        }

        state = .starting
        errorMessage = nil

        do {
            try launchHermes()
        } catch {
            errorMessage = "Failed to launch enforcement engine: \(error.localizedDescription)"
            state = .idle
            return
        }
        // Give Hermes 0.5s to start its socket server. HermesSocket.connectWithRetry
        // provides an additional 4.5s of retry budget, so this is not load-bearing.
        try? await Task.sleep(nanoseconds: 500_000_000)

        do {
            let policy = try await callOllama(rawIntent: trimmed)
            policyStore.setActivePolicy(policy)

            let taskSpec = buildTaskSpec(from: policy)
            try await hermesSocket.startSession(taskSpec)
            // PolicyStore is the sole writer of active-policy.json (Issue 6).
            // No ExtensionBridge call needed here.

            sessionStartTime = Date()
            state = .active

            // Start listening for Hermes events in the background
            Task { [weak self] in
                guard let self = self else { return }
                for await event in self.hermesSocket.events {
                    await MainActor.run {
                        self.lastHermesEvent = event
                        self.auditLog.append(event)
                    }
                }
            }
        } catch {
            // Issue 7: clear stale policy so the browser extension doesn't keep blocking
            policyStore.clearPolicy()
            hermesProcess?.terminate()
            hermesProcess = nil
            errorMessage = "Failed to start session: \(error.localizedDescription)"
            state = .idle
        }
    }

    func endSession() async {
        state = .ending

        let sessionId = policyStore.activePolicy?.sessionId ?? UUID().uuidString
        try? await hermesSocket.stopSession(sessionId: sessionId)
        // PolicyStore.clearPolicy() removes active-policy.json (Issue 6).
        // No separate extensionBridge.clearPolicy() call needed.
        writeAuditLog(sessionId: sessionId)
        policyStore.clearPolicy()
        hermesProcess?.terminate()
        hermesProcess = nil

        sessionStartTime = nil
        lastHermesEvent = nil
        auditLog = []
        state = .idle
    }

    func requestEscapeHatch(target: String) {
        state = .escapeHatch
        escapeHatchController.beginEscapeHatch(target: target)
    }

    func handleEscapeHatchGrant() {
        guard let exception = escapeHatchController.submitReason() else { return }
        policyStore.applyException(exception)
        state = .active
    }

    // MARK: - Ollama Call

    private func callOllama(rawIntent: String) async throws -> StiraPolicy {
        guard let url = URL(string: "http://localhost:11434/api/generate") else {
            throw NSError(domain: "SessionManager", code: -1, userInfo: [NSLocalizedDescriptionKey: "Invalid Ollama URL"])
        }

        let prompt = """
        /no_think
        Produce a JSON object for this focus session intent. Use EXACTLY this structure, no extra fields:
        {
          "schema_version": "1.0",
          "session_id": "<new UUID>",
          "intent": {"raw": "<original>", "normalised": "<lowercase>", "confidence": <0.7-0.99>},
          "session": {"duration_minutes": <60-120>, "hard_stop": false},
          "apps": {"mode": "block_listed", "blocked": [<app objects>], "allowed": []},
          "urls": {"rules": [<url rules>]},
          "notifications": {"mode": "suppress_all"},
          "escape_hatch": {"mode": "standard", "delay_seconds": 30, "require_reason": true, "min_reason_chars": 20, "exception_scope": "scoped", "active_exceptions": []}
        }
        Each app object: {"bundle_id": "...", "display_name": "..."}
        Each url rule: {"pattern": "domain.com", "action": "block", "reason": "...", "exceptions": []}

        App bundle IDs to choose from:
        Social: com.twitter.twittermac(Twitter), com.burbn.instagram(Instagram), com.facebook.archon(Facebook), com.reddit.reddit(Reddit), com.linkedin.LinkedIn(LinkedIn)
        Messaging: com.hnc.Discord(Discord), net.whatsapp.WhatsApp(WhatsApp), com.apple.MobileSMS(Messages), com.tinyspeck.slackmacgap(Slack), com.microsoft.teams(Teams), com.skype.skype(Skype), com.telegram.desktop(Telegram)
        Entertainment: com.spotify.client(Spotify), com.apple.Music(Music), com.apple.TV(TV), com.netflix.Netflix(Netflix), com.plexapp.plex(Plex), com.twitch.twitch(Twitch)
        Gaming: com.valvesoftware.steam(Steam), com.epicgames.EpicGamesLauncher(Epic Games), com.battle.net(Battle.net), com.riotgames.LeagueofLegends(League of Legends)
        News/distraction: com.apple.News(News), com.reeder.Reeder5(Reeder)

        URL domains to choose from:
        Social: twitter.com, x.com, instagram.com, facebook.com, reddit.com, linkedin.com, tiktok.com, tumblr.com, pinterest.com
        Entertainment: youtube.com, netflix.com, twitch.tv, primevideo.com, disneyplus.com, hulu.com, 9gag.com
        News: news.ycombinator.com, buzzfeed.com, dailymail.co.uk, tmz.com
        Shopping: amazon.com, ebay.com, etsy.com

        For CODING: block Discord, Steam, Twitter, Reddit, Spotify, WhatsApp, Messages. Block urls: twitter.com, reddit.com, youtube.com, instagram.com, facebook.com, twitch.tv, tiktok.com.
        For WRITING: block Messages, Discord, Slack, WhatsApp, Twitter, Instagram. Block urls: twitter.com, reddit.com, instagram.com, facebook.com, news.ycombinator.com, tiktok.com.
        For STUDYING: block Discord, Steam, Spotify, Music, Netflix, Twitch, Twitter, Reddit. Block urls: youtube.com, twitter.com, reddit.com, netflix.com, twitch.tv, tiktok.com, instagram.com, 9gag.com.
        For WORK/MEETINGS: block Steam, Spotify, Twitter, Reddit, Instagram, Netflix. Block urls: twitter.com, reddit.com, youtube.com, instagram.com, facebook.com, tiktok.com, amazon.com.
        For READING: block all messaging, Discord, Steam, social apps. Block all social + entertainment urls.

        Intent: \(rawIntent)
        """

        let requestBody: [String: Any] = [
            "model": "qwen3:8b",
            "prompt": prompt,
            "stream": false,
            "format": "json",
            "options": ["num_predict": 1024]
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 180

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SessionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ollama returned non-200 response"])
        }

        // The Ollama response envelope: {"model":"...","response":"<JSON string>","done":true,...}
        struct OllamaResponse: Decodable {
            let response: String
        }

        let envelope = try JSONDecoder().decode(OllamaResponse.self, from: data)
        print("[Ollama raw response]\n\(envelope.response)")

        guard let policyData = envelope.response.data(using: .utf8) else {
            throw NSError(domain: "SessionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Ollama response string"])
        }

        let decoder = JSONDecoder()
        do {
            let policy = try decoder.decode(StiraPolicy.self, from: policyData)
            return policy
        } catch {
            print("[StiraPolicy decode error] \(error)")
            throw error
        }
    }

    // MARK: - Hermes Subprocess

    private func hermesRoot() -> URL? {
        let fm = FileManager.default

        // a. Developer override via environment variable
        if let envPath = ProcessInfo.processInfo.environment["HERMES_ROOT"] {
            let url = URL(fileURLWithPath: envPath)
            if fm.fileExists(atPath: url.path) { return url }
        }

        // b. Packaged app: Resources/hermes
        if let resourceURL = Bundle.main.resourceURL {
            let candidate = resourceURL.appendingPathComponent("hermes")
            if fm.fileExists(atPath: candidate.path) { return candidate }
        }

        // c. Walk up 3 directories from executable then append "hermes"
        //    Covers .build/debug/Stira -> .build/debug -> .build -> project_root -> hermes/
        if let execURL = Bundle.main.executableURL {
            var candidate = execURL
            for _ in 0..<3 {
                candidate = candidate.deletingLastPathComponent()
            }
            let hermesCandidate = candidate.appendingPathComponent("hermes")
            if fm.fileExists(atPath: hermesCandidate.path) { return hermesCandidate }
        }

        return nil
    }

    private func findPython() -> URL? {
        let fm = FileManager.default
        let appleSilicon = URL(fileURLWithPath: "/opt/homebrew/bin/python3")
        let intelHomebrew = URL(fileURLWithPath: "/usr/local/bin/python3")

        if fm.fileExists(atPath: appleSilicon.path) { return appleSilicon }
        if fm.fileExists(atPath: intelHomebrew.path) { return intelHomebrew }
        let systemPython = URL(fileURLWithPath: "/usr/bin/python3")
        if fm.fileExists(atPath: systemPython.path) { return systemPython }
        return nil
    }

    private func launchHermes() throws {
        guard let root = hermesRoot() else {
            throw NSError(domain: "SessionManager", code: -10,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot locate Hermes directory"])
        }
        guard let python = findPython() else {
            throw NSError(domain: "SessionManager", code: -11,
                          userInfo: [NSLocalizedDescriptionKey: "Cannot locate Python 3 interpreter"])
        }

        hermesProcess?.terminate()
        hermesProcess = nil

        let process = Process()
        process.executableURL = python
        process.arguments = ["-m", "stira.main"]
        process.currentDirectoryURL = root
        process.environment = [
            "HOME": ProcessInfo.processInfo.environment["HOME"] ?? NSHomeDirectory(),
            "PATH": "/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin",
            "PYTHONUNBUFFERED": "1",
        ]
        try process.run()
        hermesProcess = process
    }

    // MARK: - Helpers

    private func buildTaskSpec(from policy: StiraPolicy) -> HermesTaskSpec {
        HermesTaskSpec(
            specVersion: "1.0",
            sessionId: policy.sessionId,
            blockedBundleIds: policy.apps.blocked.map(\.bundleId),
            allowedBundleIds: policy.apps.allowed.map(\.bundleId),
            enforcementMode: policy.apps.mode.rawValue,
            sessionDurationSeconds: policy.session.durationMinutes * 60,
            auditLevel: "standard"
        )
    }

    private func writeAuditLog(sessionId: String) {
        guard !auditLog.isEmpty else { return }
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        let sessionDir = appSupport.appendingPathComponent("Stira/sessions/\(sessionId)")
        let logFile = sessionDir.appendingPathComponent("audit.jsonl")

        do {
            try FileManager.default.createDirectory(at: sessionDir, withIntermediateDirectories: true)
            let encoder = JSONEncoder()
            let lines = try auditLog.map { event -> String in
                let data = try encoder.encode(event)
                return String(data: data, encoding: .utf8) ?? ""
            }.joined(separator: "\n")
            try lines.data(using: .utf8)?.write(to: logFile, options: .atomic)
        } catch {
            print("[SessionManager] Failed to write audit log: \(error)")
        }
    }
}
