// ExtensionBridge.swift
// Namespace for the Chrome extension bridge.
// PolicyStore is the single owner of active-policy.json.
// The StiraExtensionBridge binary reads that file directly — this class is intentionally minimal.

import Foundation

final class ExtensionBridge {
    // No-op: PolicyStore.setActivePolicy / clearPolicy manage active-policy.json.
    // This class exists as a placeholder for future IPC with the bridge process
    // (e.g. sending a "reload_rules" signal). Do not write the policy file here.
}
