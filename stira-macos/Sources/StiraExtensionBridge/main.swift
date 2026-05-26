// main.swift
// Chrome native messaging host for Stira's browser extension.
// Reads 4-byte length-prefixed JSON messages from stdin, responds to stdout.

import Foundation

// MARK: - Chrome Native Messaging I/O

func readMessage() -> [String: Any]? {
    // Read 4-byte little-endian length prefix
    var lengthBytes = [UInt8](repeating: 0, count: 4)
    let read0 = FileHandle.standardInput.availableData
    _ = read0 // warm up (unused)

    var lengthData = Data(count: 4)
    var totalRead = 0

    while totalRead < 4 {
        let chunk = FileHandle.standardInput.availableData
        if chunk.isEmpty {
            // Try blocking read
            guard let c = try? FileHandle.standardInput.read(upToCount: 4 - totalRead), !c.isEmpty else {
                return nil
            }
            for (i, byte) in c.enumerated() {
                lengthData[totalRead + i] = byte
            }
            totalRead += c.count
        } else {
            let needed = min(4 - totalRead, chunk.count)
            for i in 0..<needed {
                lengthData[totalRead + i] = chunk[i]
            }
            totalRead += needed
        }
    }

    lengthBytes = Array(lengthData)
    let length = Int(lengthBytes[0])
        | (Int(lengthBytes[1]) << 8)
        | (Int(lengthBytes[2]) << 16)
        | (Int(lengthBytes[3]) << 24)

    guard length > 0, length < 1_048_576 else { return nil }

    var messageData = Data()
    var bytesRemaining = length

    while bytesRemaining > 0 {
        guard let chunk = try? FileHandle.standardInput.read(upToCount: bytesRemaining),
              !chunk.isEmpty else {
            return nil
        }
        messageData.append(chunk)
        bytesRemaining -= chunk.count
    }

    return (try? JSONSerialization.jsonObject(with: messageData)) as? [String: Any]
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

// MARK: - Main Loop

func runLoop() {
    while true {
        guard let message = readMessage() else {
            // stdin closed — exit cleanly
            exit(0)
        }

        guard let type = message["type"] as? String else { continue }

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
}

// Entry point
runLoop()
