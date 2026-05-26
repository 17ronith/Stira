// PolicyStore.swift
// Holds the active session policy in memory and persists it to disk.

import Foundation

@MainActor
final class PolicyStore: ObservableObject {
    @Published var activePolicy: StiraPolicy?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    private var activePolicyURL: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Stira/active-policy.json")
    }

    func setActivePolicy(_ policy: StiraPolicy) {
        activePolicy = policy
        writeToDisk(policy)
    }

    func clearPolicy() {
        activePolicy = nil
        let url = activePolicyURL
        try? FileManager.default.removeItem(at: url)
    }

    func applyException(_ exception: ScopedException) {
        guard let policy = activePolicy else { return }

        let updatedExceptions = policy.escapeHatch.activeExceptions + [exception]
        let updatedEscapeHatch = EscapeHatchConfig(
            mode: policy.escapeHatch.mode,
            delaySeconds: policy.escapeHatch.delaySeconds,
            requireReason: policy.escapeHatch.requireReason,
            minReasonChars: policy.escapeHatch.minReasonChars,
            exceptionScope: policy.escapeHatch.exceptionScope,
            activeExceptions: updatedExceptions
        )

        let updatedPolicy = StiraPolicy(
            schemaVersion: policy.schemaVersion,
            sessionId: policy.sessionId,
            intent: policy.intent,
            session: policy.session,
            apps: policy.apps,
            urls: policy.urls,
            notifications: policy.notifications,
            escapeHatch: updatedEscapeHatch
        )

        activePolicy = updatedPolicy
        writeToDisk(updatedPolicy)
    }

    private func writeToDisk(_ policy: StiraPolicy) {
        let url = activePolicyURL
        do {
            let dir = url.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(policy)
            try data.write(to: url, options: .atomic)
        } catch {
            print("[PolicyStore] Failed to write policy to disk: \(error)")
        }
    }
}
