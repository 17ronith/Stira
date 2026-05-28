// GlassModifiers.swift
// Shared glassmorphism helpers used across all app views.

import SwiftUI
import AppKit

extension View {
    func glassCard(cornerRadius: CGFloat = 16, fillOpacity: Double = 0.08) -> some View {
        self
            .background(.ultraThinMaterial)
            .background(Color.white.opacity(fillOpacity))
            .clipShape(.rect(cornerRadius: cornerRadius))
            .overlay {
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Color.white.opacity(0.2), lineWidth: 0.5)
            }
    }
}

struct GlassButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// Hooks into the containing NSWindow via viewDidMoveToWindow and makes it fully
// transparent so .ultraThinMaterial renders against the real desktop behind the window.
struct WindowConfigurator: NSViewRepresentable {
    final class ConfigView: NSView {
        override func viewDidMoveToWindow() {
            super.viewDidMoveToWindow()
            guard let window, window.isOpaque else { return }
            window.isOpaque = false
            window.backgroundColor = .clear
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
            window.styleMask.insert(.fullSizeContentView)
        }
    }

    func makeNSView(context: Context) -> ConfigView { ConfigView() }
    func updateNSView(_ nsView: ConfigView, context: Context) {}
}

// Used only in #Preview blocks as a simulated desktop stand-in.
struct AppBackground: View {
    var body: some View {
        LinearGradient(
            colors: [
                Color(red: 0.06, green: 0.05, blue: 0.22),
                Color(red: 0.03, green: 0.03, blue: 0.10),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
    }
}
