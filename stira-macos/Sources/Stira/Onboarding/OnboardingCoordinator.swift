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

    private var permissionTrigger: AsyncStream<Void>.Continuation?

    func recheckPermission() {
        // AXIsProcessTrusted() is unreliable for ad-hoc signed binaries on macOS 26:
        // TCC ties the entry to the build hash, so every swift build invalidates it.
        // Trust the user's manual confirmation and finish the stream to proceed.
        permissionTrigger?.finish()
    }

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
            // Trigger the system prompt — this registers the current binary with TCC so the
            // correct entry appears in System Settings (manual "+" navigation picks wrong path).
            AXIsProcessTrustedWithOptions(["AXTrustedCheckOptionPrompt": true] as CFDictionary)
            do {
                try await awaitAccessibilityPermission()
            } catch {
                return
            }
        }

        // Install native messaging manifest for browser extension
        installNativeMessagingManifest()

        // Complete
        step = .complete
        isComplete = true
    }

    private func awaitAccessibilityPermission() async throws {
        let (stream, cont) = AsyncStream<Void>.makeStream()
        permissionTrigger = cont

        let observer = DistributedNotificationCenter.default().addObserver(
            forName: Notification.Name("com.apple.accessibility.api"),
            object: nil,
            queue: .main
        ) { _ in cont.yield() }

        let pollTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                cont.yield()
            }
        }

        defer {
            permissionTrigger = nil
            pollTask.cancel()
            DistributedNotificationCenter.default().removeObserver(observer)
            cont.finish()
        }

        for await _ in stream {
            if AXIsProcessTrusted() { return }
        }
        // Stream finished via recheckPermission() — user confirmed manually, proceed.
    }

    private func installNativeMessagingManifest() {
        // Find StiraExtensionBridge binary alongside current executable
        guard let execURL = Bundle.main.executableURL else { return }
        let bridgeBinary = execURL.deletingLastPathComponent()
            .appendingPathComponent("StiraExtensionBridge")

        guard FileManager.default.fileExists(atPath: bridgeBinary.path) else {
            // Binary not found — skip silently (happens in simulators/previews)
            return
        }

        let manifestDir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/Application Support/Google/Chrome/NativeMessagingHosts")

        let manifest: [String: Any] = [
            "name": "com.stira.extensionbridge",
            "description": "Stira browser extension bridge",
            "path": bridgeBinary.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://kceccioddldmaiodjklbpfmlmiogcbkb/"]
        ]

        do {
            try FileManager.default.createDirectory(at: manifestDir, withIntermediateDirectories: true)
            let data = try JSONSerialization.data(withJSONObject: manifest, options: [.prettyPrinted, .sortedKeys])
            let manifestURL = manifestDir.appendingPathComponent("com.stira.extensionbridge.json")
            try data.write(to: manifestURL, options: .atomic)
        } catch {
            // Non-fatal: extension won't work but enforcement still runs
            print("[OnboardingCoordinator] Failed to install native messaging manifest: \(error)")
        }
    }
}
