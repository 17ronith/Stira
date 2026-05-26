// SessionStatusView.swift
// Shows the active session: elapsed time, last Hermes event, end/break buttons.

import SwiftUI

struct SessionStatusView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var now: Date = Date()
    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    private var elapsed: String {
        guard let start = sessionManager.sessionStartTime else { return "0:00" }
        let seconds = Int(now.timeIntervalSince(start))
        let h = seconds / 3600
        let m = (seconds % 3600) / 60
        let s = seconds % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }

    var body: some View {
        VStack(spacing: 24) {
            VStack(spacing: 6) {
                Text("Session active")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(elapsed)
                    .font(.system(size: 52, weight: .thin, design: .monospaced))
            }

            if let event = sessionManager.lastHermesEvent {
                HStack(spacing: 8) {
                    Image(systemName: "shield.slash.fill")
                        .foregroundColor(.orange)
                    Text("\(event.type): \(event.bundleId ?? event.message ?? "")")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
            }

            VStack(spacing: 10) {
                Button(action: {
                    // Issue 8: use last-known blocked bundle id as the scoped exception target
                    let target = sessionManager.lastHermesEvent?.bundleId ?? "manual"
                    sessionManager.requestEscapeHatch(target: target)
                }) {
                    Text("I need a break")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(role: .destructive, action: {
                    Task { await sessionManager.endSession() }
                }) {
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
            }
        }
        .padding(24)
        .frame(minWidth: 360, minHeight: 280)
        .onReceive(timer) { newNow in
            now = newNow
        }
    }
}

#Preview {
    let sm = SessionManager()
    sm.sessionStartTime = Date().addingTimeInterval(-137)
    return SessionStatusView()
        .environmentObject(sm)
}
