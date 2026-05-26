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

func writeMessage(_ dict: [String: Any]) {
    guard let data = try? JSONSerialization.data(withJSONObject: dict) else { return }
    let length = UInt32(data.count)
    var lengthLE: UInt32 = length.littleEndian
    let lengthData = Data(bytes: &lengthLE, count: 4)
    FileHandle.standardOutput.write(lengthData)
    FileHandle.standardOutput.write(data)
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

// MARK: - Message Handling

func handleMessage(_ message: [String: Any]) {
    guard let type = message["type"] as? String else { return }

    switch type {
    case "get_policy":
        if let policy = readActivePolicy() {
            let rules = extractUrlRules(from: policy)
            writeMessage(["type": "policy", "rules": rules])
        } else {
            writeMessage(["type": "session_ended"])
        }

    default:
        writeMessage(["type": "error", "message": "Unknown message type: \(type)"])
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

// Entry point
runLoop()
