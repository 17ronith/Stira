// IntentInputView.swift
// The primary UI: user types their intent and starts a session.

import SwiftUI

struct IntentInputView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var intentText: String = ""

    private var canStart: Bool {
        sessionManager.state != .starting
            && !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What are you focusing on today?")
                .font(.title2)
                .fontWeight(.semibold)

            TextField(
                "e.g. Finish the quarterly report — no distractions",
                text: $intentText,
                axis: .vertical
            )
            .lineLimit(4...8)
            .textFieldStyle(.roundedBorder)
            .font(.body)

            if sessionManager.state == .starting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Parsing intent…")
                        .foregroundColor(.secondary)
                        .font(.subheadline)
                }
            }

            if let errorMessage = sessionManager.errorMessage {
                Text(errorMessage)
                    .foregroundColor(.red)
                    .font(.subheadline)
            }

            Button(action: {
                Task { await sessionManager.startSession(rawIntent: intentText) }
            }) {
                Text("Start Session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 240)
    }
}

#Preview("Idle") {
    IntentInputView()
        .environmentObject(SessionManager())
}

#Preview("With text") {
    let view = IntentInputView()
    return view
        .environmentObject(SessionManager())
}
