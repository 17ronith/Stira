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

    private var hasText: Bool {
        !intentText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("STIRA")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(.white.opacity(0.28))
                .kerning(3)

            VStack(alignment: .leading, spacing: 20) {
                TextField("What do you want to focus on?", text: $intentText, axis: .vertical)
                    .lineLimit(3...6)
                    .font(.system(size: 16, weight: .regular, design: .rounded))
                    .foregroundStyle(.white)
                    .textFieldStyle(.plain)
                    .tint(.white)

                Rectangle()
                    .fill(Color.white.opacity(0.12))
                    .frame(height: 0.5)

                durationRow

                if sessionManager.state == .starting {
                    HStack(spacing: 10) {
                        ProgressView()
                            .controlSize(.small)
                            .tint(.white.opacity(0.7))
                        Text("Building your focus environment…")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }

                if let error = sessionManager.errorMessage {
                    Text(error)
                        .font(.system(size: 13, design: .rounded))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .padding(24)
            .glassCard()

            if hasText {
                startButton
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .padding(32)
        .frame(minWidth: 480, minHeight: 300)
        .animation(.easeInOut(duration: 0.25), value: hasText)
    }

    // MARK: - Duration row

    private var durationRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Duration")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .kerning(1)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                ForEach(durationOptions, id: \.minutes) { option in
                    let selected = chosenDurationMinutes == option.minutes
                    Button {
                        chosenDurationMinutes = option.minutes
                    } label: {
                        Text(option.label)
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                            .foregroundStyle(selected ? .white : .white.opacity(0.45))
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color.white.opacity(selected ? 0.15 : 0.05))
                            .clipShape(.rect(cornerRadius: 8))
                            .overlay {
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(Color.white.opacity(selected ? 0.25 : 0.08), lineWidth: 0.5)
                            }
                    }
                    .buttonStyle(GlassButtonStyle())
                    .animation(.easeInOut(duration: 0.15), value: selected)
                }
            }
        }
    }

    // MARK: - Start button

    private var startButton: some View {
        Button(action: startSession) {
            HStack {
                Text("Start \(formattedDuration) session")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
            .glassCard(cornerRadius: 12, fillOpacity: 0.10)
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(!canStart)
        .opacity(canStart ? 1 : 0.5)
        .keyboardShortcut(.return, modifiers: .command)
    }

    // MARK: - Actions

    private func startSession() {
        Task {
            await sessionManager.startSession(rawIntent: intentText, durationMinutes: chosenDurationMinutes)
        }
    }

    private var formattedDuration: String {
        if chosenDurationMinutes < 60 { return "\(chosenDurationMinutes)m" }
        let h = chosenDurationMinutes / 60
        let m = chosenDurationMinutes % 60
        return m == 0 ? "\(h)h" : "\(h)h \(m)m"
    }
}

#Preview("Idle") {
    ZStack {
        AppBackground()
        IntentInputView()
    }
    .environmentObject(SessionManager())
    .preferredColorScheme(.dark)
}

#Preview("Starting") {
    let sm = SessionManager()
    sm.state = .starting
    return ZStack {
        AppBackground()
        IntentInputView()
    }
    .environmentObject(sm)
    .preferredColorScheme(.dark)
}
