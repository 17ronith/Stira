// SessionStatusView.swift
// Shows the active session: elapsed time, remaining time, blocked app pills, break/end buttons.

import SwiftUI
import AppKit

struct SessionStatusView: View {
    @EnvironmentObject var sessionManager: SessionManager
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var now: Date = Date()
    @State private var showEndConfirmation: Bool = false
    @State private var showToast = false
    @State private var toastBundleId: String?
    @State private var toastDisplayName: String?
    @State private var toastDismissTask: Task<Void, Never>?
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    // MARK: - Time computations

    private var elapsed: String {
        guard let start = sessionManager.sessionStartTime else { return "0:00" }
        let seconds = Int(now.timeIntervalSince(start))
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    private var remainingInfo: (text: String, warning: Bool)? {
        guard let start = sessionManager.sessionStartTime,
              let policy = sessionManager.policyStore.activePolicy,
              policy.session.durationMinutes > 0 else { return nil }
        let totalSec = policy.session.durationMinutes * 60
        let elapsedSec = Int(now.timeIntervalSince(start))
        let left = max(0, totalSec - elapsedSec)
        let mins = left / 60
        let secs = left % 60
        let text = left < 60 ? "\(secs)s left" : "\(mins)m left"
        return (text: text, warning: left < 5 * 60)
    }

    private var intentText: String {
        sessionManager.policyStore.activePolicy?.intent.normalised ?? ""
    }

    private var blockedApps: [AppRule] {
        sessionManager.policyStore.activePolicy?.apps.blocked ?? []
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 28) {
            clockSection
            if !blockedApps.isEmpty { blockingSection }
            buttonSection
        }
        .padding(32)
        .frame(minWidth: 420, minHeight: 380)
        .onReceive(ticker) { newNow in now = newNow }
        .overlay(alignment: .top) {
            if showToast, let name = toastDisplayName {
                blockedToastPill(bundleId: toastBundleId, name: name)
                    .transition(reduceMotion ? .opacity : .scale(scale: 0.85, anchor: .top).combined(with: .opacity))
                    .padding(.top, 16)
            }
        }
        .onChange(of: sessionManager.lastHermesEvent) { _, event in
            print("[SessionStatusView] onChange fired: \(String(describing: event?.type))")
            guard let event,
                  event.type == "app_blocked" || event.type == "focus_killed",
                  let bundleId = event.bundleId else { return }
            let name = blockedApps.first { $0.bundleId == bundleId }?.displayName
                ?? bundleId.components(separatedBy: ".").last?.capitalized
                ?? bundleId
            print("[SessionStatusView] triggering toast for \(bundleId)")
            triggerBlockedToast(bundleId: bundleId, displayName: name)
        }
    }

    // MARK: - Clock

    private var clockSection: some View {
        VStack(spacing: 6) {
            if !intentText.isEmpty {
                Text(intentText)
                    .font(.system(size: 12, weight: .regular, design: .rounded))
                    .foregroundStyle(.white.opacity(0.45))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }

            Text(elapsed)
                .font(.system(size: 56, weight: .thin, design: .rounded))
                .foregroundStyle(.white)
                .monospacedDigit()

            if let remaining = remainingInfo {
                Text(remaining.text)
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                    .foregroundStyle(remaining.warning ? Color(red: 1, green: 0.65, blue: 0.3) : .white.opacity(0.45))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 4)
                    .background(Color.white.opacity(remaining.warning ? 0.08 : 0.04))
                    .clipShape(.capsule)
                    .animation(.easeInOut, value: remaining.warning)
            }
        }
    }

    // MARK: - Blocking section

    private var blockingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Blocking")
                .font(.system(size: 10, weight: .semibold, design: .rounded))
                .foregroundStyle(.white.opacity(0.35))
                .kerning(1)
                .textCase(.uppercase)

            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                ForEach(blockedApps, id: \.bundleId) { app in
                    blockedPill(app: app)
                }
            }
        }
        .padding(16)
        .glassCard(cornerRadius: 12, fillOpacity: 0.05)
    }

    private func blockedPill(app: AppRule) -> some View {
        HStack(spacing: 6) {
            appIcon(bundleId: app.bundleId)
                .frame(width: 16, height: 16)
            Text(app.displayName.isEmpty ? app.bundleId : app.displayName)
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.75))
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .glassCard(cornerRadius: 8, fillOpacity: 0.05)
    }

    // MARK: - Buttons

    private var buttonSection: some View {
        VStack(spacing: 10) {
            Button(action: sessionManager.requestEscapeHatch) {
                Text("I need a blocked app")
                    .font(.system(size: 14, weight: .medium, design: .rounded))
                    .foregroundStyle(.white.opacity(0.85))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .glassCard(cornerRadius: 12, fillOpacity: 0.08)
            }
            .buttonStyle(GlassButtonStyle())

            endSessionButton
        }
    }

    @ViewBuilder
    private var endSessionButton: some View {
        Button(role: .destructive) {
            showEndConfirmation = true
        } label: {
            Group {
                if sessionManager.state == .ending {
                    ProgressView()
                        .controlSize(.small)
                        .tint(.red.opacity(0.8))
                } else {
                    Text("End Session")
                        .font(.system(size: 14, weight: .medium, design: .rounded))
                        .foregroundStyle(.red.opacity(0.8))
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .glassCard(cornerRadius: 12, fillOpacity: 0.05)
        }
        .buttonStyle(GlassButtonStyle())
        .disabled(sessionManager.state == .ending)
        .confirmationDialog(
            "End your focus session?",
            isPresented: $showEndConfirmation,
            titleVisibility: .visible
        ) {
            Button("Goal achieved — I'm done") {
                Task { await sessionManager.endSession() }
            }
            Button("End early", role: .destructive) {
                Task { await sessionManager.endSession() }
            }
            Button("Keep going", role: .cancel) { }
        } message: {
            if let remaining = remainingInfo {
                Text("You have \(remaining.text) in your session.")
            } else {
                Text("Your session will stop and enforcement will be lifted.")
            }
        }
    }

    // MARK: - Helpers

    private func appIcon(bundleId: String) -> some View {
        Group {
            if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleId) {
                let nsImage = NSWorkspace.shared.icon(forFile: url.path)
                Image(nsImage: nsImage)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "app.fill")
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
    }

    // MARK: - Blocked toast

    private func triggerBlockedToast(bundleId: String, displayName: String) {
        toastDismissTask?.cancel()
        toastBundleId = bundleId
        toastDisplayName = displayName

        // FocusKiller activates Finder after each block, pushing Stira behind it.
        // Bring the Stira window back to front so the toast is actually visible.
        NSApp.activate(ignoringOtherApps: true)
        NSApp.windows.first(where: { !$0.isMiniaturized })?.makeKeyAndOrderFront(nil)

        withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
            showToast = true
        }
        toastDismissTask = Task {
            try? await Task.sleep(for: .seconds(3.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.spring(response: 0.4, dampingFraction: 0.78)) {
                    showToast = false
                }
            }
        }
    }

    private func blockedToastPill(bundleId: String?, name: String) -> some View {
        HStack(spacing: 8) {
            if let id = bundleId {
                appIcon(bundleId: id)
                    .frame(width: 20, height: 20)
            }
            Text("\(name) blocked")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.white.opacity(0.85))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassCard(cornerRadius: 20, fillOpacity: 0.3)
    }
}

#Preview {
    let sm = SessionManager()
    sm.sessionStartTime = Date().addingTimeInterval(-137)
    return ZStack {
        AppBackground()
        SessionStatusView()
    }
    .environmentObject(sm)
    .preferredColorScheme(.dark)
}
