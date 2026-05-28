// SessionStatusView.swift
// Shows the active session: elapsed time, remaining time, last Hermes event, break/end buttons.

import SwiftUI

struct SessionStatusView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var now: Date = Date()
    @State private var showEndConfirmation: Bool = false
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Time computations

    private var elapsed: String {
        guard let start = sessionManager.sessionStartTime else { return "0:00" }
        let seconds = Int(now.timeIntervalSince(start))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var remainingInfo: (text: String, warning: Bool)? {
        guard let start = sessionManager.sessionStartTime,
              let policy = sessionManager.policyStore.activePolicy,
              policy.session.durationMinutes > 0 else { return nil }
        let totalSec = policy.session.durationMinutes * 60
        let elapsedSec = Int(now.timeIntervalSince(start))
        let left = max(0, totalSec - elapsedSec)
        let mins = left / 60
        let secs = left % 60
        let text = left < 60 ? "\(secs)s left" : "\(mins)m left"
        return (text: text, warning: left < 5 * 60)
    }

    private var policyContext: String {
        guard let policy = sessionManager.policyStore.activePolicy else { return "" }
        let total = policy.session.durationMinutes
        let durationLabel = total == 0 ? "" : " · \(total)m session"
        return policy.intent.normalised + durationLabel
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 24) {
            clockSection
            policyHintSection
            eventSection
            buttonSection
        }
        .padding(24)
        .frame(minWidth: 380, minHeight: 300)
        .onReceive(ticker) { newNow in now = newNow }
    }

    // MARK: - Sub-sections

    private var clockSection: some View {
        VStack(spacing: 4) {
            Text("Session active")
                .font(.headline)
                .foregroundStyle(.secondary)

            Text(elapsed)
                .font(.system(size: 52, weight: .thin, design: .monospaced))

            if let remaining = remainingInfo {
                Text(remaining.text)
                    .font(.subheadline)
                    .foregroundStyle(remaining.warning ? .orange : .secondary)
                    .animation(.easeInOut, value: remaining.warning)
            }
        }
    }

    private var policyHintSection: some View {
        Group {
            if !policyContext.isEmpty {
                Text(policyContext)
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
        }
    }

    private var eventSection: some View {
        Group {
            if let event = sessionManager.lastHermesEvent {
                Label(
                    "\(event.type): \(event.bundleId ?? event.message ?? "")",
                    systemImage: "shield.slash.fill"
                )
                .font(.subheadline)
                .foregroundStyle(.orange)
                .lineLimit(1)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.1))
                .clipShape(.rect(cornerRadius: 8))
            }
        }
    }

    private var buttonSection: some View {
        VStack(spacing: 10) {
            Button {
                sessionManager.requestEscapeHatch()
            } label: {
                Text("Need to access a blocked app")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)

            endSessionButton
        }
    }

    @ViewBuilder
    private var endSessionButton: some View {
        Button(role: .destructive) {
            showEndConfirmation = true
        } label: {
            if sessionManager.state == .ending {
                ProgressView()
                    .controlSize(.small)
                    .frame(maxWidth: .infinity)
            } else {
                Text("End Session")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.borderedProminent)
        .tint(.red)
        .disabled(sessionManager.state == .ending)
        .confirmationDialog(
            "End your focus session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Goal achieved — I'm done") {
                Task { await sessionManager.endSession() }
            }
            Button("End early", role: .destructive) {
                Task { await sessionManager.endSession() }
            }
            Button("Keep going", role: .cancel) { }
        } message: {
            if let remaining = remainingInfo {
                Text("You have \(remaining.text) in your session.")
            } else {
                Text("Your session will stop and enforcement will be lifted.")
            }
        }
    }
}

#Preview {
    let sm = SessionManager()
    sm.sessionStartTime = Date().addingTimeInterval(-137)
    return SessionStatusView()
        .environmentObject(sm)
}
