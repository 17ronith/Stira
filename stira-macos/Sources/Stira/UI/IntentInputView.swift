// IntentInputView.swift
// The primary UI: intent text field, duration picker, and Start Session button.

import SwiftUI

struct IntentInputView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @State private var intentText: String = ""
    @State private var chosenDurationMinutes: Int = 60

    private let durationOptions: [(label: String, minutes: Int)] = [
        ("30m", 30), ("45m", 45), ("1h", 60), ("90m", 90), ("2h", 120)
    ]

    private var canStart: Bool {
        sessionManager.state != .starting
            && !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("What are you focusing on today?")
                .font(.title2)
                .bold()

            TextField(
                "e.g. Finish the quarterly report — no distractions",
                text: $intentText,
                axis: .vertical
            )
            .lineLimit(4...8)
            .textFieldStyle(.roundedBorder)
            .font(.body)

            durationPickerRow

            if sessionManager.state == .starting {
                HStack(spacing: 10) {
                    ProgressView()
                        .controlSize(.small)
                    Text("Parsing intent…")
                        .foregroundStyle(.secondary)
                        .font(.subheadline)
                }
            }

            if let errorMessage = sessionManager.errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
                    .font(.subheadline)
            }

            Button {
                Task {
                    await sessionManager.startSession(
                        rawIntent: intentText,
                        durationMinutes: chosenDurationMinutes
                    )
                }
            } label: {
                Text("Start \(formattedDuration) session")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!canStart)
            .keyboardShortcut(.return, modifiers: .command)
        }
        .padding(24)
        .frame(minWidth: 480, minHeight: 260)
    }

    // MARK: - Duration picker

    private var durationPickerRow: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Duration")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            HStack(spacing: 8) {
                ForEach(durationOptions, id: \.minutes) { option in
                    Toggle(isOn: Binding(
                        get: { chosenDurationMinutes == option.minutes },
                        set: { if $0 { chosenDurationMinutes = option.minutes } }
                    )) {
                        Text(option.label)
                    }
                    .toggleStyle(.button)
                    .buttonStyle(.bordered)
                }
            }
        }
    }

    // MARK: - Helpers

    private var formattedDuration: String {
        if chosenDurationMinutes < 60 { return "\(chosenDurationMinutes)m" }
        let h = chosenDurationMinutes / 60
        let m = chosenDurationMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h\(m)m"
    }
}

#Preview("Idle") {
    IntentInputView()
        .environmentObject(SessionManager())
}

#Preview("Starting") {
    let sm = SessionManager()
    sm.state = .starting
    return IntentInputView()
        .environmentObject(sm)
}
