// StiraApp.swift
// Entry point for the Stira macOS application.

import SwiftUI
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if !hasVisibleWindows {
            for window in sender.windows { window.makeKeyAndOrderFront(nil) }
        }
        sender.activate(ignoringOtherApps: true)
        return true
    }
}

public struct StiraApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    public init() {}

    @StateObject private var sessionManager = SessionManager()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()

    public var body: some Scene {
        WindowGroup {
            rootView
                .preferredColorScheme(.dark)
                .environmentObject(sessionManager)
                .environmentObject(onboardingCoordinator)
                .task { await onboardingCoordinator.start() }
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
                .background(WindowConfigurator())
                .sheet(isPresented: Binding(
                    get: { sessionManager.state == .escapeHatch },
                    set: { _ in }
                )) {
                    EscapeHatchView(controller: sessionManager.escapeHatchController)
                        .environmentObject(sessionManager)
                        .interactiveDismissDisabled(true)
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }

    @ViewBuilder
    private var rootView: some View {
        if onboardingCoordinator.isComplete {
            contentView
        } else {
            OnboardingView()
                .environmentObject(onboardingCoordinator)
        }
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
}
