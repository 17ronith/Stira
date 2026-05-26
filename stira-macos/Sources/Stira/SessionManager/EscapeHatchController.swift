// EscapeHatchController.swift
// Manages the Standard-mode escape hatch UX: 30s immovable countdown, typed reason, scoped exception.

import Foundation
import Combine

@MainActor
final class EscapeHatchController: ObservableObject {
    enum EscapeHatchState: Equatable {
        case idle
        case countdown(remaining: Int)
        case reasonEntry
        case granted
    }

    @Published var state: EscapeHatchState = .idle
    @Published var reason: String = ""
    var currentTarget: String?

    private var countdownTimer: Timer?

    var isReasonValid: Bool {
        reason.count >= 20
    }

    func beginEscapeHatch(target: String) {
        currentTarget = target
        reason = ""
        state = .countdown(remaining: 30)
        startCountdown()
    }

    func cancelCountdown() {
        // Intentionally a no-op: the countdown cannot be cancelled.
    }

    func submitReason() -> ScopedException? {
        guard isReasonValid else { return nil }

        let now = Date()
        let expires = now.addingTimeInterval(30 * 60) // 30-minute scoped exception
        let isoFormatter = ISO8601DateFormatter()

        let exception = ScopedException(
            exceptionId: UUID().uuidString,
            targetType: .app,
            target: currentTarget ?? "unknown",
            grantedAt: isoFormatter.string(from: now),
            expiresAt: isoFormatter.string(from: expires),
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
                guard let self = self else {
                    timer.invalidate()
                    return
                }
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
