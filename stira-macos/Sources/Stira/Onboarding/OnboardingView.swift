// OnboardingView.swift
// Container view that renders the correct onboarding screen based on coordinator step.

import SwiftUI

struct OnboardingView: View {
    @EnvironmentObject var coordinator: OnboardingCoordinator

    var body: some View {
        Group {
            switch coordinator.step {
            case .checkingRAM, .installingOllama:
                settingUpView
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .downloadingModel(let progress):
                ModelDownloadView(progress: progress)
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .awaitingPermission:
                PermissionOnboardingView()
                    .transition(.asymmetric(
                        insertion: .move(edge: .trailing).combined(with: .opacity),
                        removal: .move(edge: .leading).combined(with: .opacity)
                    ))

            case .complete:
                EmptyView()

            case .failed(let message):
                failureView(message: message)
                    .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.4), value: coordinator.step)
    }

    // MARK: - Subviews

    private var settingUpView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.2)
                .tint(.white.opacity(0.7))

            VStack(spacing: 4) {
                Text("Getting ready")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)
                Text("Checking your system and installing dependencies…")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }
        }
        .padding(40)
        .glassCard(cornerRadius: 20, fillOpacity: 0.07)
        .frame(width: 400)
        .padding(40)
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 24) {
            Image(systemName: "xmark.circle.fill")
                .font(.system(size: 44, design: .rounded))
                .foregroundStyle(.white.opacity(0.6))

            VStack(spacing: 6) {
                Text("Setup failed")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Quit Stira") {
                NSApplication.shared.terminate(nil)
            }
            .font(.system(size: 14, weight: .medium, design: .rounded))
            .foregroundStyle(.white.opacity(0.8))
            .padding(.horizontal, 24)
            .padding(.vertical, 12)
            .glassCard(cornerRadius: 10, fillOpacity: 0.08)
            .buttonStyle(GlassButtonStyle())
        }
        .padding(40)
        .glassCard(cornerRadius: 20, fillOpacity: 0.07)
        .frame(width: 400)
        .padding(40)
    }
}

// MARK: - Previews

#Preview("Setting up") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .installingOllama
    return ZStack {
        AppBackground()
        OnboardingView()
    }
    .environmentObject(coordinator)
    .preferredColorScheme(.dark)
}

#Preview("Downloading model") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .downloadingModel(progress: 0.42)
    return ZStack {
        AppBackground()
        OnboardingView()
    }
    .environmentObject(coordinator)
    .preferredColorScheme(.dark)
}

#Preview("Awaiting permission") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .awaitingPermission
    return ZStack {
        AppBackground()
        OnboardingView()
    }
    .environmentObject(coordinator)
    .preferredColorScheme(.dark)
}

#Preview("Failed") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .failed("Stira requires at least 8 GB of RAM. This Mac has 4.0 GB.")
    return ZStack {
        AppBackground()
        OnboardingView()
    }
    .environmentObject(coordinator)
    .preferredColorScheme(.dark)
}
