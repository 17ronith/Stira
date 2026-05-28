// PermissionOnboardingView.swift
// Prompts the user to grant Accessibility access.

import SwiftUI
import AppKit

struct PermissionOnboardingView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator

    private let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("One permission needed")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("Stira suppresses distracting apps in the background. macOS requires Accessibility access to do this.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            settingsGuide

            VStack(spacing: 10) {
                Button(action: openSystemSettings) {
                    Text("Open System Settings")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 13)
                        .glassCard(cornerRadius: 10, fillOpacity: 0.10)
                }
                .buttonStyle(GlassButtonStyle())

                Button("I've granted permission — continue") {
                    coordinator.recheckPermission()
                }
                .font(.system(size: 13, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .buttonStyle(GlassButtonStyle())
            }
        }
        .padding(36)
        .glassCard(cornerRadius: 20, fillOpacity: 0.07)
        .frame(width: 420)
        .padding(40)
    }

    // MARK: - Settings guide diagram

    private var settingsGuide: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("How to grant access")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .kerning(1)
                .textCase(.uppercase)

            HStack(spacing: 6) {
                pathStep(icon: "gearshape.fill", label: "System\nSettings")

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))

                pathStep(icon: "hand.raised.fill", label: "Privacy &\nSecurity")

                Image(systemName: "chevron.right")
                    .font(.system(size: 10))
                    .foregroundStyle(.white.opacity(0.25))

                pathStep(icon: "figure.arms.open", label: "Accessibility")

                Spacer()
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.turn.down.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.white.opacity(0.3))

                Text("Find \"Stira\" in the list and toggle it ON")
                    .font(.system(size: 12, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
            }
            .padding(.leading, 4)
        }
        .padding(16)
        .glassCard(cornerRadius: 12, fillOpacity: 0.05)
    }

    private func pathStep(icon: String, label: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 18))
                .foregroundStyle(.white.opacity(0.65))
                .frame(width: 38, height: 38)
                .background(Color.white.opacity(0.08))
                .clipShape(.rect(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .stroke(Color.white.opacity(0.15), lineWidth: 0.5)
                }

            Text(label)
                .font(.system(size: 9, design: .rounded))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .frame(width: 50)
        }
    }

    // MARK: - Actions

    private func openSystemSettings() {
        NSWorkspace.shared.open(accessibilityURL)
    }
}

#Preview {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .awaitingPermission
    return ZStack {
        AppBackground()
        PermissionOnboardingView()
    }
    .environmentObject(coordinator)
    .preferredColorScheme(.dark)
}
