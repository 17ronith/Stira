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

        guard let schemaData = StiraPolicy.schemaJSON.data(using: .utf8),
              let schemaObj = try? JSONSerialization.jsonObject(with: schemaData) else {
            throw NSError(domain: "SessionManager", code: -2, userInfo: [NSLocalizedDescriptionKey: "Failed to parse policy schema"])
        }

        let prompt = """
        You are a focus session policy engine. Given the user's intent, produce a StiraPolicy JSON object.
        Use schema_version "1.0". Generate a unique UUID for session_id.
        Set intent.raw to the original input, intent.normalised to a lowercase version, intent.confidence to a value between 0.7-0.99.
        Set session.duration_minutes to a reasonable value (60-120 for most tasks, 0 if indefinite), session.hard_stop to false.
        For apps, choose mode "block_listed" and list commonly distracting apps for the stated task.
        For urls, list commonly distracting URLs as blocked rules.
        Set notifications.mode to "suppress_all".
        Set escape_hatch.mode to "standard", delay_seconds to 30, require_reason to true, min_reason_chars to 20, exception_scope to "scoped", active_exceptions to [].

        User intent: \(rawIntent)
        """

        let requestBody: [String: Any] = [
            "model": "qwen3:8b",
            "prompt": prompt,
            "stream": false,
            "format": schemaObj
        ]

        let bodyData = try JSONSerialization.data(withJSONObject: requestBody)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = bodyData
        request.timeoutInterval = 60

        let (data, response) = try await URLSession.shared.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw NSError(domain: "SessionManager", code: -3, userInfo: [NSLocalizedDescriptionKey: "Ollama returned non-200 response"])
        }

        // The Ollama response envelope: {"model":"...","response":"<JSON string>","done":true,...}
        struct OllamaResponse: Decodable {
            let response: String
        }

        let envelope = try JSONDecoder().decode(OllamaResponse.self, from: data)

        guard let policyData = envelope.response.data(using: .utf8) else {
            throw NSError(domain: "SessionManager", code: -4, userInfo: [NSLocalizedDescriptionKey: "Failed to decode Ollama response string"])
        }

        let decoder = JSONDecoder()
        let policy = try decoder.decode(StiraPolicy.self, from: policyData)
        return policy
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
