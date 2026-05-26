// main.swift
// Chrome native messaging host for Stira's browser extension.
// Reads 4-byte length-prefixed JSON messages from stdin, responds to stdout.

import Foundation

// MARK: - Chrome Native Messaging I/O

func readExactly(_ count: Int) -> Data? {
    var buffer = Data(count: count)
    var totalRead = 0
    while totalRead < count {
        let bytesRead = buffer.withUnsafeMutableBytes { ptr in
            Foundation.read(STDIN_FILENO, ptr.baseAddress! + totalRead, count - totalRead)
        }
        if bytesRead <= 0 { return nil }
        totalRead += bytesRead
    }
    return buffer
}

// Issue 5: Three-state return:
//   .none          → EOF / clean shutdown → caller should exit
//   .some(.none)   → parse / length error → caller should log and continue
//   .some(.some)   → valid message
func readMessage() -> [String: Any]?? {
    guard let lenBytes = readExactly(4) else {
        // EOF on the length bytes — clean shutdown
        return .some(nil)
    }
    let length = lenBytes.withUnsafeBytes { $0.load(as: UInt32.self).littleEndian }
    guard length > 0, length < 1_000_000 else {
        fputs("[StiraExtensionBridge] invalid message length: \(length)\n", stderr)
        // Invalid length — skip and keep looping (outer nil = continue)
        return nil
    }
    guard let body = readExactly(Int(length)) else {
        // EOF mid-message — treat as shutdown
        return .some(nil)
    }
    guard let msg = try? JSONSerialization.jsonObject(with: body) as? [String: Any] else {
        fputs("[StiraExtensionBridge] JSON parse error — skipping frame\n", stderr)
        return nil
    }
    return .some(msg)
}

// MARK: - Policy Reading

func readActivePolicy() -> [String: Any]? {
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!
    let policyURL = appSupport.appendingPathComponent("Stira/active-policy.json")

    guard let data = try? Data(contentsOf: policyURL),
          let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
        return nil
    }
    return json
}

func extractUrlRules(from policy: [String: Any]) -> [[String: Any]] {
    guard let urls = policy["urls"] as? [String: Any],
          let rules = urls["rules"] as? [[String: Any]] else {
        return []
    }

    var result: [[String: Any]] = []

    for rule in rules {
        guard let pattern = rule["pattern"] as? String,
              let action = rule["action"] as? String else {
            continue
        }

        var transformed: [String: Any] = [
            "pattern": pattern,
            "action": action
        ]

        if let exceptions = rule["exceptions"] as? [[String: Any]] {
            transformed["exceptions"] = exceptions.compactMap { exc -> [String: Any]? in
                guard let p = exc["pattern"] as? String else { return nil }
                return ["pattern": p]
            }
        }

        result.append(transformed)
    }

    return result
}

// MARK: - Thread-safe stdout

// writeMessage can be called from both the main thread (responding to get_policy)
// and the policy-watcher background thread — serialize all stdout writes.
let writeLock = NSLock()

func writeMessageSafe(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    var length = UInt32(data.count).littleEndian
    writeLock.lock()
    defer { writeLock.unlock() }
    let lengthData = Data(bytes: &length, count: 4)
    FileHandle.standardOutput.write(lengthData)
    FileHandle.standardOutput.write(data)
}

// MARK: - Policy File Watcher

// The extension connects once on startup and waits for push notifications.
// When the Swift app writes active-policy.json (session start), we push
// policy_update. When the file is deleted (session end), we push session_ended.
func startPolicyWatcher() {
    let appSupport = FileManager.default.urls(
        for: .applicationSupportDirectory,
        in: .userDomainMask
    ).first!
    let policyURL = appSupport.appendingPathComponent("Stira/active-policy.json")

    Thread.detachNewThread {
        var lastMtime: Date? = nil
        var lastExists = false

        while true {
            Thread.sleep(forTimeInterval: 1.0)

            let exists = FileManager.default.fileExists(atPath: policyURL.path)
            let currentMtime = exists
                ? (try? FileManager.default.attributesOfItem(atPath: policyURL.path))?[.modificationDate] as? Date
                : nil

            if exists && (!lastExists || currentMtime != lastMtime) {
                // File appeared or was modified — push updated rules to extension
                if let policy = readActivePolicy() {
                    let rules = extractUrlRules(from: policy)
                    writeMessageSafe(["type": "policy_update", "rules": rules])
                }
            } else if !exists && lastExists {
                // File was deleted — session ended
                writeMessageSafe(["type": "session_ended"])
            }

            lastExists = exists
            lastMtime = currentMtime
        }
    }
}

// MARK: - Message Handling

func handleMessage(_ message: [String: Any]) {
    guard let type = message["type"] as? String else { return }

    switch type {
    case "get_policy":
        if let policy = readActivePolicy() {
            let rules = extractUrlRules(from: policy)
            writeMessageSafe(["type": "policy", "rules": rules])
        } else {
            writeMessageSafe(["type": "session_ended"])
        }

    default:
        writeMessageSafe(["type": "error", "message": "Unknown message type: \(type)"])
    }
}

// MARK: - Main Loop

func runLoop() {
    while true {
        switch readMessage() {
        case .none:
            // Parse / length error — log and continue
            fputs("[StiraExtensionBridge] skipping malformed message\n", stderr)
            continue
        case .some(.none):
            // EOF — exit cleanly
            exit(0)
        case .some(.some(let message)):
            handleMessage(message)
        }
    }
}

// Entry point: start file watcher, then block on Chrome stdin
startPolicyWatcher()
runLoop()
