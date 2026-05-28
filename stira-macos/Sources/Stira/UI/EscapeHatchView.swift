// EscapeHatchView.swift
// Standard-mode escape hatch: app picker → 30s countdown → reason → granted.

import SwiftUI
import AppKit

struct EscapeHatchView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @ObservedObject var controller: EscapeHatchController

    private var currentIntent: String {
        sessionManager.policyStore.activePolicy?.intent.normalised ?? "your focus goal"
    }

    var body: some View {
        Group {
            switch controller.state {
            case .appPicker:
                appPickerView
                    .transition(.opacity)
            case .countdown(let remaining):
                countdownView(remaining: remaining)
                    .transition(.opacity)
            case .reasonEntry:
                reasonEntryView
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            case .granted:
                grantedView
                    .transition(.opacity)
            case .idle:
                EmptyView()
            }
        }
        .animation(.easeInOut(duration: 0.4), value: controller.state)
        .frame(minWidth: 420, minHeight: 420)
        .preferredColorScheme(.dark)
        .background(WindowConfigurator())
    }

    // MARK: - App Picker

    @State private var customAppName: String = ""

    private var installedBlockedApps: [AppRule] {
        controller.blockedApps.filter {
            NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0.bundleId) != nil
        }
    }

    private var appPickerView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Which app do you need?")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("A 30-second pause helps you decide if it's worth it.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            if !installedBlockedApps.isEmpty {
                VStack(spacing: 6) {
                    ScrollView {
                        VStack(spacing: 6) {
                            ForEach(installedBlockedApps, id: \.bundleId) { app in
                                appRow(app: app)
                            }
                        }
                    }
                    .scrollIndicators(.hidden)
                    .frame(maxHeight: 180)

                    Rectangle()
                        .fill(Color.white.opacity(0.1))
                        .frame(height: 0.5)

                    customAppField
                }
            } else {
                customAppField
            }

            Button {
                sessionManager.state = .active
                controller.reset()
            } label: {
                Text("Stay focused")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .glassCard(cornerRadius: 10, fillOpacity: 0.04)
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(28)
    }

    private func appRow(app: AppRule) -> some View {
        Button {
            controller.selectApp(bundleId: app.bundleId, displayName: app.displayName)
        } label: {
            HStack(spacing: 12) {
                appIcon(bundleId: app.bundleId)
                    .frame(width: 26, height: 26)
                Text(app.displayName.isEmpty ? app.bundleId : app.displayName)
                    .font(.system(size: 14, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.25))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 10, fillOpacity: 0.06)
        }
        .buttonStyle(GlassButtonStyle())
    }

    private var customAppField: some View {
        HStack(spacing: 8) {
            TextField("Other app name…", text: $customAppName)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .tint(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 10)
                .glassCard(cornerRadius: 10, fillOpacity: 0.06)

            Button("Open") {
                guard !customAppName.trimmingCharacters(in: .whitespaces).isEmpty else { return }
                controller.selectCustomApp(name: customAppName)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.85))
            .padding(.horizontal, 14)
            .padding(.vertical, 10)
            .glassCard(cornerRadius: 10, fillOpacity: 0.08)
            .buttonStyle(GlassButtonStyle())
            .disabled(customAppName.trimmingCharacters(in: .whitespaces).isEmpty)
        }
    }

    // MARK: - Countdown

    private func countdownView(remaining: Int) -> some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("You asked to focus on \(currentIntent)")
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                Text("What's pulling you away?")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            ZStack {
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 4)
                    .frame(width: 110, height: 110)

                Circle()
                    .trim(from: 0, to: CGFloat(remaining) / 30.0)
                    .stroke(Color.white.opacity(0.7), style: StrokeStyle(lineWidth: 4, lineCap: .round))
                    .frame(width: 110, height: 110)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1), value: remaining)

                Text("\(remaining)")
                    .font(.system(size: 36, weight: .thin, design: .rounded))
                    .foregroundStyle(.white)
            }

            Text("If you still need \(controller.currentTargetDisplayName ?? "it") after this, you can explain why.")
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.45))
                .multilineTextAlignment(.center)
                .frame(maxWidth: 280)

            Button {
                sessionManager.state = .active
                controller.reset()
            } label: {
                Text("Actually, I'm fine — stay focused")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
            }
            .buttonStyle(GlassButtonStyle())
        }
        .padding(28)
    }

    // MARK: - Reason Entry

    private var reasonEntryView: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Why do you need \(controller.currentTargetDisplayName ?? "this app")?")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Unblocked for 30 minutes. Your session stays active.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }

            VStack(alignment: .trailing, spacing: 6) {
                TextField(
                    "e.g. Check message from cofounder about the launch",
                    text: $controller.reason,
                    axis: .vertical
                )
                .lineLimit(3...6)
                .font(.system(size: 14, design: .rounded))
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .tint(.white)
                .padding(14)
                .glassCard(cornerRadius: 12, fillOpacity: 0.07)

                let remaining = max(0, 20 - controller.reason.count)
                Text(remaining > 0 ? "\(remaining) more characters" : "Good to go")
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(.white.opacity(remaining > 0 ? 0.35 : 0.5))
            }

            HStack(spacing: 10) {
                Button {
                    sessionManager.state = .active
                    controller.reset()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(cornerRadius: 10, fillOpacity: 0.05)
                }
                .buttonStyle(GlassButtonStyle())

                Button {
                    sessionManager.handleEscapeHatchGrant()
                } label: {
                    Text("Unlock \(controller.currentTargetDisplayName ?? "app")")
                        .font(.system(size: 14, weight: .semibold, design: .rounded))
                        .foregroundStyle(controller.isReasonValid ? .white : .white.opacity(0.35))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(cornerRadius: 10, fillOpacity: controller.isReasonValid ? 0.12 : 0.04)
                }
                .buttonStyle(GlassButtonStyle())
                .disabled(!controller.isReasonValid)
                .animation(.easeInOut(duration: 0.2), value: controller.isReasonValid)
            }
        }
        .padding(28)
    }

    // MARK: - Granted

    private var grantedView: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))

            VStack(spacing: 4) {
                Text("\(controller.currentTargetDisplayName ?? "App") is unlocked")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Unblocked for 30 minutes. Your focus session continues.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                if let bundleId = controller.currentTarget {
                    Button {
                        openApp(bundleId: bundleId)
                    } label: {
                        Text("Open \(controller.currentTargetDisplayName ?? "App")")
                            .font(.system(size: 14, weight: .medium, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 13)
                            .glassCard(cornerRadius: 10, fillOpacity: 0.10)
                    }
                    .buttonStyle(GlassButtonStyle())
                }

                Button {
                    sessionManager.state = .active
                } label: {
                    Text("Back to my session")
                        .font(.system(size: 14, design: .rounded))
                        .foregroundStyle(.white.opacity(0.55))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(cornerRadius: 10, fillOpacity: 0.04)
                }
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(28)
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
                    .font(.body)
                    .foregroundStyle(.white.opacity(0.3))
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
