// EscapeHatchController.swift
// Manages the Standard-mode escape hatch UX:
// .appPicker → .countdown(30s) → .reasonEntry → .granted

import Foundation
import Combine

@MainActor
final class EscapeHatchController: ObservableObject {
    enum EscapeHatchState: Equatable {
        case idle
        case appPicker
        case countdown(remaining: Int)
        case reasonEntry
        case granted
    }

    @Published var state: EscapeHatchState = .idle
    @Published var reason: String = ""

    /// Bundle ID of the app the user chose, or nil for custom-named apps.
    var currentTarget: String?
    /// Display name shown in the UI during countdown, reason entry, and granted phases.
    var currentTargetDisplayName: String?
    /// Apps from the active policy that the picker offers.
    var blockedApps: [AppRule] = []

    private var countdownTimer: Timer?

    var isReasonValid: Bool { reason.count >= 20 }

    // MARK: - New flow

    /// Phase 1: show the picker. Call `selectApp` or `selectCustomApp` to advance.
    func beginEscapeHatch(blockedApps: [AppRule]) {
        self.blockedApps = blockedApps
        reason = ""
        currentTarget = nil
        currentTargetDisplayName = nil
        state = .appPicker
    }

    /// Phase 2: user chose a policy-blocked app by bundle ID.
    func selectApp(bundleId: String, displayName: String) {
        currentTarget = bundleId
        currentTargetDisplayName = displayName.isEmpty ? bundleId : displayName
        state = .countdown(remaining: 30)
        startCountdown()
    }

    /// Phase 2 (alt): user typed a custom app name not in the blocked list.
    func selectCustomApp(name: String) {
        currentTarget = nil
        currentTargetDisplayName = name.isEmpty ? "the app" : name
        state = .countdown(remaining: 30)
        startCountdown()
    }

    func cancelCountdown() {
        // Intentionally a no-op: the countdown is immovable by design.
    }

    func reset() {
        countdownTimer?.invalidate()
        countdownTimer = nil
        state = .idle
        reason = ""
        currentTarget = nil
        currentTargetDisplayName = nil
        blockedApps = []
    }

    func submitReason() -> ScopedException? {
        guard isReasonValid else { return nil }

        let now = Date()
        let expires = now.addingTimeInterval(30 * 60)
        let iso = ISO8601DateFormatter()

        let exception = ScopedException(
            exceptionId: UUID().uuidString,
            targetType: .app,
            target: currentTarget ?? currentTargetDisplayName ?? "unknown",
            grantedAt: iso.string(from: now),
            expiresAt: iso.string(from: expires),
            reason: reason
        )

        state = .granted
        return exception
    }

    // MARK: - Private

    private func startCountdown() {
        countdownTimer?.invalidate()
        var remaining = 30

        countdownTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] timer in
            Task { @MainActor [weak self] in
                guard let self else { timer.invalidate(); return }
                remaining -= 1
                if remaining > 0 {
                    self.state = .countdown(remaining: remaining)
                } else {
                    timer.invalidate()
                    self.countdownTimer = nil
                    self.state = .reasonEntry
                }
            }
        }
    }
}
