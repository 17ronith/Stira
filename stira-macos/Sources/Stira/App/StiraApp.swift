// StiraApp.swift
// Entry point for the Stira macOS application.

import SwiftUI
import AppKit

public struct StiraApp: App {
    public init() {}

    @StateObject private var sessionManager = SessionManager()
    @StateObject private var onboardingCoordinator = OnboardingCoordinator()

    public var body: some Scene {
        WindowGroup {
            rootView
                .environmentObject(sessionManager)
                .environmentObject(onboardingCoordinator)
                .task { await onboardingCoordinator.start() }
                .onAppear { NSApp.activate(ignoringOtherApps: true) }
                .sheet(isPresented: Binding(
                    get: { sessionManager.state == .escapeHatch },
                    set: { _ in }
                )) {
                    EscapeHatchView(controller: sessionManager.escapeHatchController)
                        .environmentObject(sessionManager)
                        .interactiveDismissDisabled(true)
                }
        }
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
