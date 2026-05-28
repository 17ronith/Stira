// EscapeHatchView.swift
// Standard-mode escape hatch: 30s immovable countdown, then neutral reason prompt.

import SwiftUI

struct EscapeHatchView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject var controller: EscapeHatchController

    var body: some View {
        Group {
            switch controller.state {
            case .appPicker:
                appPickerView
            case .countdown(let remaining):
                countdownView(remaining: remaining)
            case .reasonEntry:
                reasonEntryView
            case .granted:
                grantedView
            case .idle:
                EmptyView()
            }
        }
        .frame(minWidth: 360, minHeight: 240)
        .padding(28)
    }

    // MARK: - App Picker

    @State private var customAppName: String = ""

    private var appPickerView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Which app do you need?")
                .font(.title3)
                .fontWeight(.semibold)

            if !controller.blockedApps.isEmpty {
                VStack(spacing: 8) {
                    ForEach(controller.blockedApps, id: \.bundleId) { app in
                        Button(action: {
                            controller.selectApp(bundleId: app.bundleId, displayName: app.displayName)
                        }) {
                            HStack {
                                Text(app.displayName.isEmpty ? app.bundleId : app.displayName)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.secondary)
                                    .font(.caption)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                        }
                        .buttonStyle(.bordered)
                    }
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Or name another app:")
                    .font(.subheadline)
                    .foregroundColor(.secondary)

                HStack {
                    TextField("App name", text: $customAppName)
                        .textFieldStyle(.roundedBorder)

                    Button("Continue") {
                        controller.selectCustomApp(name: customAppName)
                    }
                    .disabled(customAppName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    // MARK: - Countdown

    private func countdownView(remaining: Int) -> some View {
        VStack(spacing: 20) {
            Text("Hold on…")
                .font(.title2)
                .fontWeight(.semibold)

            ZStack {
                Circle()
                    .stroke(Color.secondary.opacity(0.2), lineWidth: 6)
                    .frame(width: 90, height: 90)

                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 30.0)
                    .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                    .frame(width: 90, height: 90)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)

                Text("\(remaining)")
                    .font(.system(size: 30, weight: .medium, design: .monospaced))
            }

            Text("You asked to stay focused — just a moment.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }

    // MARK: - Reason Entry

    private var reasonEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("You asked to focus — what changed?")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This exception will only apply for this specific app or URL, not your whole session.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "What do you need to access?",
                    text: $controller.reason,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

                Text("\(controller.reason.count) / 20 chars minimum")
                    .font(.caption)
                    .foregroundColor(controller.isReasonValid ? .green : .secondary)
            }

            Button(action: {
                sessionManager.handleEscapeHatchGrant()
            }) {
                Text("Allow exception")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .disabled(!controller.isReasonValid)
        }
    }

    // MARK: - Granted

    private var grantedView: some View {
        VStack(spacing: 16) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundColor(.green)

            Text("Exception granted")
                .font(.title3)
                .fontWeight(.semibold)

            Text("This exception has been logged. Returning to your session.")
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview("Countdown") {
    let controller = EscapeHatchController()
    controller.state = .countdown(remaining: 18)
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}

#Preview("Reason entry") {
    let controller = EscapeHatchController()
    controller.state = .reasonEntry
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}

#Preview("Granted") {
    let controller = EscapeHatchController()
    controller.state = .granted
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}
