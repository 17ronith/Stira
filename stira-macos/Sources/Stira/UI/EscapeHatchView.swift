// EscapeHatchView.swift
// Standard-mode escape hatch: app picker → 30s countdown → reason → granted.

import SwiftUI
import AppKit

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
        .frame(minWidth: 380, minHeight: 260)
        .padding(28)
    }

    // MARK: - App Picker

    @State private var customAppName: String = ""

    private var appPickerView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which app do you need?")
                    .font(.title2)
                    .bold()
                Text("A 30-second pause helps you make a mindful decision.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !controller.blockedApps.isEmpty {
                VStack(spacing: 6) {
                    ForEach(controller.blockedApps, id: \.bundleId) { app in
                        appRow(app: app)
                    }
                    Divider()
                    customAppField
                }
            } else {
                customAppField
            }

            Button(role: .cancel) {
                sessionManager.state = .active
                controller.reset()
            } label: {
                Text("Stay focused")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
    }

    private func appRow(app: AppRule) -> some View {
        Button {
            controller.selectApp(bundleId: app.bundleId, displayName: app.displayName)
        } label: {
            HStack(spacing: 12) {
                appIcon(bundleId: app.bundleId)
                    .frame(width: 28, height: 28)
                Text(app.displayName.isEmpty ? app.bundleId : app.displayName)
                    .font(.body)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.tertiary)
                    .font(.caption)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.quaternary.opacity(0.5))
            .clipShape(.rect(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }

    private var customAppField: some View {
        HStack(spacing: 8) {
            TextField("Other app name…", text: $customAppName)
                .textFieldStyle(.roundedBorder)
            Button("Open") {
                guard !customAppName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                controller.selectCustomApp(name: customAppName)
            }
            .buttonStyle(.bordered)
            .disabled(customAppName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Countdown

    private func countdownView(remaining: Int) -> some View {
        VStack(spacing: 20) {
            VStack(spacing: 4) {
                Text("Opening \(controller.currentTargetDisplayName ?? "app")…")
                    .font(.title2)
                    .bold()
                Text("30 seconds — time to make a mindful call.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle()
                    .stroke(.secondary.opacity(0.2), lineWidth: 6)
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

            Text("If you still need \(controller.currentTargetDisplayName ?? "it") after this, tell us why.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Button(role: .cancel) {
                sessionManager.state = .active
                controller.reset()
            } label: {
                Text("Actually, I'm fine — stay focused")
            }
            .buttonStyle(.plain)
            .foregroundStyle(.secondary)
            .font(.subheadline)
        }
    }

    // MARK: - Reason Entry

    private var reasonEntryView: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why do you need \(controller.currentTargetDisplayName ?? "this app")?")
                    .font(.title3)
                    .bold()
                Text("This unblocks \(controller.currentTargetDisplayName ?? "the app") for 30 minutes. Your session stays active.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            VStack(alignment: .trailing, spacing: 4) {
                TextField(
                    "e.g. Check message from cofounder about the launch",
                    text: $controller.reason,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .textFieldStyle(.roundedBorder)

                if controller.reason.count < 20 {
                    Text("\(20 - controller.reason.count) more characters")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    Label("Good", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
            }

            HStack(spacing: 10) {
                Button(role: .cancel) {
                    sessionManager.state = .active
                    controller.reset()
                } label: {
                    Text("Cancel")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button {
                    sessionManager.handleEscapeHatchGrant()
                } label: {
                    Text("Unlock \(controller.currentTargetDisplayName ?? "app")")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!controller.isReasonValid)
            }
        }
    }

    // MARK: - Granted

    private var grantedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 44))
                .foregroundStyle(.green)

            VStack(spacing: 4) {
                Text("\(controller.currentTargetDisplayName ?? "App") is unlocked")
                    .font(.title3)
                    .bold()
                Text("Unblocked for 30 minutes. Your focus session continues.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                if let bundleId = controller.currentTarget {
                    Button {
                        openApp(bundleId: bundleId)
                    } label: {
                        Label(
                            "Open \(controller.currentTargetDisplayName ?? "App")",
                            systemImage: "arrow.up.right.square"
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                }

                Button {
                    sessionManager.state = .active
                } label: {
                    Text("Back to my session")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
    }

    // MARK: - Helpers

    private func openApp(bundleId: String) {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
            NSWorkspace.shared.open(url)
        }
    }

    private func appIcon(bundleId: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let nsImage = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.title2)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview("App Picker") {
    let controller = EscapeHatchController()
    controller.beginEscapeHatch(blockedApps: [
        AppRule(bundleId: "com.hnc.Discord", displayName: "Discord"),
        AppRule(bundleId: "net.whatsapp.WhatsApp", displayName: "WhatsApp"),
        AppRule(bundleId: "com.spotify.client", displayName: "Spotify"),
    ])
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}

#Preview("Countdown") {
    let controller = EscapeHatchController()
    controller.currentTargetDisplayName = "WhatsApp"
    controller.state = .countdown(remaining: 18)
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}

#Preview("Reason entry") {
    let controller = EscapeHatchController()
    controller.currentTargetDisplayName = "WhatsApp"
    controller.currentTarget = "net.whatsapp.WhatsApp"
    controller.state = .reasonEntry
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}

#Preview("Granted") {
    let controller = EscapeHatchController()
    controller.currentTargetDisplayName = "WhatsApp"
    controller.currentTarget = "net.whatsapp.WhatsApp"
    controller.state = .granted
    return EscapeHatchView(controller: controller)
        .environmentObject(SessionManager())
}
