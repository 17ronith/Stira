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

            case .downloadingModel(let progress):
                ModelDownloadView(progress: progress)

            case .awaitingPermission:
                PermissionOnboardingView()

            case .complete:
                EmptyView()

            case .failed(let message):
                failureView(message: message)
            }
        }
        .animation(.easeInOut(duration: 0.25), value: coordinator.step)
    }

    // MARK: - Subviews

    private var settingUpView: some View {
        VStack(spacing: 20) {
            Spacer()
            ProgressView()
                .scaleEffect(1.5)
            Text("Setting up…")
                .font(.title3)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(width: 440, height: 260)
        .padding(40)
    }

    private func failureView(message: String) -> some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "xmark.octagon.fill")
                .font(.system(size: 48))
                .foregroundStyle(.red)

            VStack(spacing: 8) {
                Text("Setup failed")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Button("Quit") {
                NSApplication.shared.terminate(nil)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .controlSize(.large)

            Spacer()
        }
        .padding(40)
        .frame(width: 440, height: 300)
    }
}

// MARK: - Previews

#Preview("Setting up") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .installingOllama
    return OnboardingView()
        .environmentObject(coordinator)
}

#Preview("Downloading model") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .downloadingModel(progress: 0.42)
    return OnboardingView()
        .environmentObject(coordinator)
}

#Preview("Awaiting permission") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .awaitingPermission
    return OnboardingView()
        .environmentObject(coordinator)
}

#Preview("Failed") {
    let coordinator = OnboardingCoordinator()
    coordinator.step = .failed("Stira requires at least 8 GB of RAM. This Mac has 4.0 GB.")
    return OnboardingView()
        .environmentObject(coordinator)
}
