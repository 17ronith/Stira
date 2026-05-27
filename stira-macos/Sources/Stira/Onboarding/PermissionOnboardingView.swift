// PermissionOnboardingView.swift
// Prompts the user to grant Accessibility access.

import SwiftUI
import AppKit

struct PermissionOnboardingView: View {
    private let accessibilityURL = URL(
        string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
    )!

    var body: some View {
        VStack(spacing: 28) {
            Spacer()

            Image(systemName: "hand.raised.fill")
                .font(.system(size: 48))
                .foregroundStyle(.blue)

            VStack(spacing: 10) {
                Text("One permission needed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Stira suppresses distracting apps in the background. macOS requires Accessibility access to do this.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button(action: openSystemSettings) {
                Label("Open System Settings", systemImage: "gearshape")
                    .frame(minWidth: 200)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)

            Text("Come back here after granting access — Stira will continue automatically.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)

            Spacer()
        }
        .padding(40)
        .frame(width: 440, height: 320)
    }

    private func openSystemSettings() {
        NSWorkspace.shared.open(accessibilityURL)
    }
}

#Preview {
    PermissionOnboardingView()
}
