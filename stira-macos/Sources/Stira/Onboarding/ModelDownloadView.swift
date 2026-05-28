// ModelDownloadView.swift
// Shown while qwen3:8b is being pulled from Ollama.

import SwiftUI

struct ModelDownloadView: View {
    let progress: Double

    private var isIndeterminate: Bool { progress <= 0 }

    var body: some View {
        VStack(spacing: 28) {
            VStack(spacing: 6) {
                Text("Downloading AI model")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(.white)

                Text("One-time 5 GB download — this is what understands your intent.")
                    .font(.system(size: 13, design: .rounded))
                    .foregroundStyle(.white.opacity(0.5))
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 10) {
                glassProgressBar
                    .frame(maxWidth: 300)

                if !isIndeterminate {
                    Text("\(Int(progress * 100))%")
                        .font(.system(size: 12, weight: .medium, design: .rounded))
                        .foregroundStyle(.white.opacity(0.4))
                        .monospacedDigit()
                }
            }
        }
        .padding(40)
        .glassCard(cornerRadius: 20, fillOpacity: 0.07)
        .frame(width: 400)
        .padding(40)
    }

    private var glassProgressBar: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.1))

                if isIndeterminate {
                    Capsule()
                        .fill(Color.white.opacity(0.5))
                        .frame(width: geo.size.width * 0.3)
                } else {
                    Capsule()
                        .fill(Color.white.opacity(0.75))
                        .frame(width: geo.size.width * progress)
                        .animation(.easeInOut(duration: 0.4), value: progress)
                }
            }
        }
        .frame(height: 4)
        .overlay {
            Capsule()
                .stroke(Color.white.opacity(0.1), lineWidth: 0.5)
        }
    }
}

#Preview("Indeterminate") {
    ZStack {
        AppBackground()
        ModelDownloadView(progress: 0)
    }
    .preferredColorScheme(.dark)
}

#Preview("42%") {
    ZStack {
        AppBackground()
        ModelDownloadView(progress: 0.42)
    }
    .preferredColorScheme(.dark)
}
