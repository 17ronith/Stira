// OllamaInstaller.swift
// Handles Ollama binary installation and model management.

import Foundation
import AppKit

enum InstallPhase: Equatable {
    case idle
    case downloading(progress: Double)
    case installing
    case done
    case failed(String)
}

@MainActor
final class OllamaInstaller: ObservableObject {
    @Published var phase: InstallPhase = .idle

    private let ollamaURL = URL(string: "https://ollama.com/download/Ollama-darwin.zip")!
    private let baseURL = URL(string: "http://localhost:11434")!

    // C1: instance variable so it's not deallocated mid-download
    private var downloadSession: URLSession?

    // MARK: - Public API

    // I5: ensureOllama now throws instead of only communicating failure via phase
    func ensureOllama() async throws {
        if await isOllamaRunning() {
            phase = .done
            return
        }

        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let userAppsOllama = homeDir.appendingPathComponent("Applications/Ollama.app")

        // M1: check Intel (/usr/local/bin), Apple Silicon (/opt/homebrew/bin), and ~/Applications
        let binaryExists = FileManager.default.fileExists(atPath: "/usr/local/bin/ollama")
            || FileManager.default.fileExists(atPath: "/opt/homebrew/bin/ollama")
            || FileManager.default.fileExists(atPath: userAppsOllama.path)

        if !binaryExists {
            await installOllama()
        } else {
            // Binary exists but daemon not running — launch it
            await launchOllamaApp()
        }

        // Wait for daemon to be ready (up to 30s)
        for _ in 0..<30 {
            if await isOllamaRunning() {
                phase = .done
                return
            }
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        phase = .failed("Ollama did not start within 30 seconds.")

        // I5: propagate failure as a thrown error
        if case .failed(let msg) = phase {
            throw OllamaError.startupFailed(msg)
        }
    }

    func isOllamaRunning() async -> Bool {
        let url = baseURL.appendingPathComponent("api/version")
        var request = URLRequest(url: url)
        request.timeoutInterval = 2

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    func isModelPulled(_ model: String) async -> Bool {
        let url = baseURL.appendingPathComponent("api/tags")
        var request = URLRequest(url: url)
        request.timeoutInterval = 5

        do {
            let (data, response) = try await URLSession.shared.data(for: request)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return false }
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            let models = json?["models"] as? [[String: Any]] ?? []
            return models.contains { ($0["name"] as? String)?.hasPrefix(model) == true }
        } catch {
            return false
        }
    }

    func pullModel(_ model: String, progress: @escaping (Double) -> Void) async throws {
        let url = baseURL.appendingPathComponent("api/pull")
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: ["name": model, "stream": true])

        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw OllamaError.unexpectedStatus
        }

        // C2: accumulate bytes into a [UInt8] buffer, decode at newline boundaries
        var lineBuffer: [UInt8] = []
        for try await byte in bytes {
            if byte == UInt8(ascii: "\n") {
                if !lineBuffer.isEmpty,
                   let line = String(bytes: lineBuffer, encoding: .utf8)?
                       .trimmingCharacters(in: .whitespaces),
                   !line.isEmpty,
                   let data = line.data(using: .utf8) {
                    if let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                        if let status = event["status"] as? String, status == "success" {
                            progress(1.0)
                            return
                        }
                        if let completed = event["completed"] as? Double,
                           let total = event["total"] as? Double,
                           total > 0 {
                            progress(completed / total)
                        }
                    }
                }
                lineBuffer.removeAll()
            } else {
                lineBuffer.append(byte)
            }
        }
    }

    // MARK: - Private

    private func installOllama() async {
        phase = .downloading(progress: 0)

        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("stira-ollama-\(UUID().uuidString)")

        // I2/I3: defer cleanup so it runs on every exit path
        defer {
            try? FileManager.default.removeItem(at: tempDir)
        }

        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
            let zipPath = tempDir.appendingPathComponent("Ollama-darwin.zip")

            // C1: store session as instance variable so it isn't deallocated mid-download
            let delegate = DownloadProgressDelegate { [weak self] p in
                Task { @MainActor in
                    self?.phase = .downloading(progress: p)
                }
            }
            downloadSession = URLSession(configuration: .default, delegate: delegate, delegateQueue: nil)
            let (tempFile, _) = try await downloadSession!.download(from: ollamaURL)

            // I4: invalidate session after download completes
            downloadSession?.finishTasksAndInvalidate()
            downloadSession = nil

            try FileManager.default.moveItem(at: tempFile, to: zipPath)

            phase = .installing

            // C3: wrap waitUntilExit in async continuation to avoid blocking @MainActor
            let unzipProcess = Process()
            unzipProcess.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
            unzipProcess.arguments = ["-xk", zipPath.path, tempDir.path]

            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                unzipProcess.terminationHandler = { p in
                    if p.terminationStatus == 0 {
                        cont.resume()
                    } else {
                        cont.resume(throwing: OllamaError.unzipFailed)
                    }
                }
                do {
                    try unzipProcess.run()
                } catch {
                    cont.resume(throwing: error)
                }
            }

            let extractedApp = tempDir.appendingPathComponent("Ollama.app")

            // I1: install to ~/Applications instead of /Applications (no elevated privileges needed)
            let homeDir = FileManager.default.homeDirectoryForCurrentUser
            let userAppsDir = homeDir.appendingPathComponent("Applications")
            let destination = userAppsDir.appendingPathComponent("Ollama.app")

            if !FileManager.default.fileExists(atPath: userAppsDir.path) {
                try FileManager.default.createDirectory(at: userAppsDir, withIntermediateDirectories: true)
            }

            if FileManager.default.fileExists(atPath: destination.path) {
                try FileManager.default.removeItem(at: destination)
            }
            try FileManager.default.moveItem(at: extractedApp, to: destination)

            await launchOllamaApp()

        } catch {
            // I4: also invalidate session on failure
            downloadSession?.finishTasksAndInvalidate()
            downloadSession = nil
            phase = .failed(error.localizedDescription)
        }
    }

    private func launchOllamaApp() async {
        // I1: launch from ~/Applications/Ollama.app
        let homeDir = FileManager.default.homeDirectoryForCurrentUser
        let appURL = homeDir.appendingPathComponent("Applications/Ollama.app")
        guard FileManager.default.fileExists(atPath: appURL.path) else { return }
        let config = NSWorkspace.OpenConfiguration()
        config.activates = false
        _ = try? await NSWorkspace.shared.openApplication(at: appURL, configuration: config)
    }
}

// MARK: - Errors

enum OllamaError: LocalizedError {
    case unexpectedStatus
    case unzipFailed
    case startupFailed(String)

    var errorDescription: String? {
        switch self {
        case .unexpectedStatus: return "Unexpected response from Ollama server."
        case .unzipFailed: return "Failed to unzip Ollama archive."
        case .startupFailed(let msg): return msg
        }
    }
}

// MARK: - Download Progress Delegate

private final class DownloadProgressDelegate: NSObject, URLSessionDownloadDelegate {
    let onProgress: (Double) -> Void

    init(onProgress: @escaping (Double) -> Void) {
        self.onProgress = onProgress
    }

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didFinishDownloadingTo location: URL
    ) {}

    func urlSession(
        _ session: URLSession,
        downloadTask: URLSessionDownloadTask,
        didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64,
        totalBytesExpectedToWrite: Int64
    ) {
        guard totalBytesExpectedToWrite > 0 else { return }
        onProgress(Double(totalBytesWritten) / Double(totalBytesExpectedToWrite))
    }
}
