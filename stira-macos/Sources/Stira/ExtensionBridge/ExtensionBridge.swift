// ExtensionBridge.swift
// Writes/clears the active policy JSON file read by the Chrome extension bridge binary.

import Foundation

final class ExtensionBridge {
    private let activePolicyPath: URL = {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("Stira/active-policy.json")
    }()

    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        return e
    }()

    func pushPolicy(_ policy: StiraPolicy) {
        do {
            let dir = activePolicyPath.deletingLastPathComponent()
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            let data = try encoder.encode(policy)
            try data.write(to: activePolicyPath, options: .atomic)
        } catch {
            print("[ExtensionBridge] Failed to write policy: \(error)")
        }
    }

    func clearPolicy() {
        try? FileManager.default.removeItem(at: activePolicyPath)
    }
}
