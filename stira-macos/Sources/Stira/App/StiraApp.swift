// StiraApp.swift
// Entry point for the Stira macOS application.

import SwiftUI
import AppKit

@main
struct StiraApp: App {
    @StateObject private var sessionManager = SessionManager()

    init() {
        checkRAM()
    }

    var body: some Scene {
        WindowGroup {
            contentView
                .environmentObject(sessionManager)
                .sheet(isPresented: Binding(
                    get: { sessionManager.state == .escapeHatch },
                    set: { _ in }
                )) {
                    EscapeHatchView(controller: sessionManager.escapeHatchController)
                        .environmentObject(sessionManager)
                }
        }
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var contentView: some View {
        switch sessionManager.state {
        case .idle, .starting:
            IntentInputView()
        case .active, .escapeHatch, .ending:
            SessionStatusView()
        }
    }

    // MARK: - RAM Check

    private func checkRAM() {
        let gbRAM = Double(ProcessInfo.processInfo.physicalMemory) / 1_073_741_824
        if gbRAM < 8.0 {
            DispatchQueue.main.async {
                let alert = NSAlert()
                alert.messageText = "Insufficient Memory"
                alert.informativeText = "Stira requires at least 8 GB of RAM to run the local AI model. This Mac has \(String(format: "%.1f", gbRAM)) GB."
                alert.alertStyle = .critical
                alert.addButton(withTitle: "Quit")
                alert.runModal()
                NSApplication.shared.terminate(nil)
            }
        }
    }
}
