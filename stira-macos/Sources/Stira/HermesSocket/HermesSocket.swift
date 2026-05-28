// HermesSocket.swift
// Unix domain socket client for communicating with the Hermes enforcement subprocess.

import Foundation
import Darwin

// MARK: - Message Types

struct HermesTaskSpec: Codable {
    let specVersion: String
    let sessionId: String
    let blockedBundleIds: [String]
    let allowedBundleIds: [String]
    let enforcementMode: String
    let sessionDurationSeconds: Int
    let auditLevel: String

    enum CodingKeys: String, CodingKey {
        case specVersion = "spec_version"
        case sessionId = "session_id"
        case blockedBundleIds = "blocked_bundle_ids"
        case allowedBundleIds = "allowed_bundle_ids"
        case enforcementMode = "enforcement_mode"
        case sessionDurationSeconds = "session_duration_seconds"
        case auditLevel = "audit_level"
    }
}

struct HermesEvent: Codable {
    let type: String
    let sessionId: String
    let timestamp: String
    let bundleId: String?
    let message: String?

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case timestamp
        case bundleId = "bundle_id"
        case message
    }
}

// MARK: - Start/Stop Message Envelopes

private struct StartSessionMessage: Codable {
    let type: String
    let policy: HermesTaskSpec
}

private struct StopSessionMessage: Codable {
    let type: String
    let sessionId: String

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
    }
}

private struct ApplyExceptionMessage: Codable {
    let type: String
    let sessionId: String
    let bundleId: String

    enum CodingKeys: String, CodingKey {
        case type
        case sessionId = "session_id"
        case bundleId = "bundle_id"
    }
}

// MARK: - HermesSocket

@MainActor
final class HermesSocket: ObservableObject {
    private let socketPath: String = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Stira/hermes.sock").path
    }()

    private var socketFd: Int32 = -1
    private var _eventsContinuation: AsyncStream<HermesEvent>.Continuation?

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        return d
    }()

    // MARK: - Public API

    // Issue 1: regular stored var, initialised in init so events are never missed
    var events: AsyncStream<HermesEvent>

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: HermesEvent.self)
        self.events = stream
        self._eventsContinuation = continuation
    }

    // Issue 1: create a fresh stream for each new session so second sessions work
    private func resetEventStream() {
        _eventsContinuation?.finish()
        let (stream, continuation) = AsyncStream.makeStream(of: HermesEvent.self)
        self.events = stream
        self._eventsContinuation = continuation
    }

    func startSession(_ taskSpec: HermesTaskSpec) async throws {
        // Issue 1: reset stream before each session
        resetEventStream()

        try await connectWithRetry()

        let message = StartSessionMessage(type: "start_session", policy: taskSpec)
        let data = try encoder.encode(message)
        var line = data
        line.append(0x0A) // newline

        // Issue 3B: close fd if write fails after connect
        do {
            try write(data: line)
        } catch {
            Darwin.close(socketFd)
            socketFd = -1
            throw error
        }

        // Start reading events in background
        Task.detached { [weak self] in
            await self?.readEventLoop()
        }
    }

    func stopSession(sessionId: String) async throws {
        guard socketFd >= 0 else { return }

        // Issue 4: shut down the read side so readEventLoop sees EOF and exits
        // before the fd is closed and potentially recycled
        Darwin.shutdown(socketFd, SHUT_RD)

        // Issue 3A: always close fd via defer even if write throws
        defer {
            if socketFd >= 0 {
                Darwin.close(socketFd)
                socketFd = -1
            }
        }

        let message = StopSessionMessage(type: "stop_session", sessionId: sessionId)
        let data = try encoder.encode(message)
        var line = data
        line.append(0x0A)
        try write(data: line)
    }

    func applyException(sessionId: String, bundleId: String) throws {
        guard socketFd >= 0 else { return }

        let message = ApplyExceptionMessage(type: "apply_exception", sessionId: sessionId, bundleId: bundleId)
        let data = try encoder.encode(message)
        var line = data
        line.append(0x0A) // newline
        try write(data: line)
    }

    // MARK: - Connection

    private func connectWithRetry() async throws {
        var lastError: Error = NSError(domain: "HermesSocket", code: -1, userInfo: [NSLocalizedDescriptionKey: "Failed to connect after retries"])
        for attempt in 0..<10 {
            do {
                try connectSocket()
                return
            } catch {
                lastError = error
                if attempt < 9 {
                    try await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
        throw lastError
    }

    private func connectSocket() throws {
        let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            throw NSError(domain: "HermesSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "socket() failed: \(errno)"])
        }

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)

        let pathBytes = socketPath.utf8CString
        let maxLen = MemoryLayout.size(ofValue: addr.sun_path)
        guard pathBytes.count <= maxLen else {
            Darwin.close(fd)
            throw NSError(domain: "HermesSocket", code: -2, userInfo: [NSLocalizedDescriptionKey: "Socket path too long"])
        }

        withUnsafeMutablePointer(to: &addr.sun_path) { ptr in
            pathBytes.withUnsafeBufferPointer { src in
                UnsafeMutableRawPointer(ptr).copyMemory(
                    from: src.baseAddress!,
                    byteCount: min(src.count, maxLen)
                )
            }
        }

        let addrLen = socklen_t(MemoryLayout<sockaddr_un>.size)
        let result = withUnsafePointer(to: &addr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockPtr in
                Darwin.connect(fd, sockPtr, addrLen)
            }
        }

        guard result == 0 else {
            Darwin.close(fd)
            throw NSError(domain: "HermesSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "connect() failed: \(errno)"])
        }

        // Issue 2: suppress SIGPIPE so a dead Hermes doesn't kill the Swift process
        var nosigpipe: Int32 = 1
        Darwin.setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &nosigpipe, socklen_t(MemoryLayout<Int32>.size))

        socketFd = fd
    }

    // MARK: - Write

    private func write(data: Data) throws {
        guard socketFd >= 0 else {
            throw NSError(domain: "HermesSocket", code: -3, userInfo: [NSLocalizedDescriptionKey: "Socket not connected"])
        }
        var remaining = data
        while !remaining.isEmpty {
            let written = remaining.withUnsafeBytes { ptr in
                Darwin.write(socketFd, ptr.baseAddress!, ptr.count)
            }
            if written == -1 {
                // Issue (minor): retry on EINTR, throw on all other errors
                if errno == EINTR { continue }
                throw NSError(domain: "HermesSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "write() failed: \(errno)"])
            }
            if written == 0 {
                throw NSError(domain: "HermesSocket", code: Int(errno), userInfo: [NSLocalizedDescriptionKey: "write() returned 0"])
            }
            remaining = remaining.dropFirst(written)
        }
    }

    // MARK: - Read Loop

    private func readEventLoop() async {
        let fd = await MainActor.run { socketFd }
        guard fd >= 0 else { return }

        var buffer = Data()
        let chunkSize = 4096

        while true {
            var chunk = Data(count: chunkSize)
            let bytesRead = chunk.withUnsafeMutableBytes { ptr in
                Darwin.read(fd, ptr.baseAddress!, chunkSize)
            }

            if bytesRead <= 0 { break }

            buffer.append(chunk.prefix(bytesRead))

            // Parse newline-delimited JSON
            while let newlineRange = buffer.range(of: Data([0x0A])) {
                let lineData = buffer[buffer.startIndex..<newlineRange.lowerBound]
                buffer.removeSubrange(buffer.startIndex...newlineRange.lowerBound)

                if let event = try? decoder.decode(HermesEvent.self, from: lineData) {
                    let capturedEvent = event
                    _ = await MainActor.run {
                        self._eventsContinuation?.yield(capturedEvent)
                    }
                }
            }
        }

        // Signal end to the continuation (but do NOT finish — resetEventStream handles lifecycle)
        await MainActor.run {
            _eventsContinuation?.finish()
            _eventsContinuation = nil
        }
    }
}
