// OnboardingCoordinator.swift
// Orchestrates the full onboarding flow: RAM → Ollama → model → permission → complete.

import Foundation
import ApplicationServices

enum OnboardingStep: Equatable {
    case checkingRAM
    case installingOllama
    case downloadingModel(progress: Double)
    case awaitingPermission
    case complete
    case failed(String)
}

@MainActor
final class OnboardingCoordinator: ObservableObject {
    @Published var step: OnboardingStep = .checkingRAM
    @Published var isComplete: Bool = false

    let ollamaInstaller = OllamaInstaller()

    func start() async {
        // Step 1: RAM check
        step = .checkingRAM
        let gbRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if gbRAM < 8.0 {
            step = .failed("Stira requires at least 8 GB of RAM to run the local AI model. This Mac has \(String(format: "%.1f", gbRAM)) GB.")
            return
        }

        // Step 2: Ensure Ollama is installed and running
        // I5: ensureOllama now throws — catch to set step = .failed(...)
        step = .installingOllama
        do {
            try await ollamaInstaller.ensureOllama()
        } catch {
            step = .failed(error.localizedDescription)
            return
        }

        // Step 3: Pull model if not already present
        let modelName = "qwen3:8b"
        let alreadyPulled = await ollamaInstaller.isModelPulled(modelName)
        if !alreadyPulled {
            step = .downloadingModel(progress: 0)
            do {
                // C5: guard against stale progress callbacks arriving after step has moved on
                try await ollamaInstaller.pullModel(modelName) { [weak self] p in
                    Task { @MainActor [weak self] in
                        guard let self, case .downloadingModel = self.step else { return }
                        self.step = .downloadingModel(progress: p)
                    }
                }
            } catch {
                step = .failed("Failed to download AI model: \(error.localizedDescription)")
                return
            }
        }

        // Step 4: Accessibility permission
        if !AXIsProcessTrusted() {
            step = .awaitingPermission
            // C4: use try await (not try?) so CancellationError propagates and exits the loop cleanly
            do {
                while !AXIsProcessTrusted() {
                    try await Task.sleep(nanoseconds: 2_000_000_000)
                }
            } catch {
                // Task was cancelled — exit without completing
                return
            }
        }

        // Complete
        step = .complete
        isComplete = true
    }
}
