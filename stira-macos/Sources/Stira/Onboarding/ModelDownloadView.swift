// ModelDownloadView.swift
// Shown while qwen3:8b is being pulled from Ollama.

import SwiftUI

struct ModelDownloadView: View {
    let progress: Double

    private var isIndeterminate: Bool { progress <= 0 }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 8) {
                Text("Downloading AI model")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("One-time 5 GB download — this is what understands your intent.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            VStack(spacing: 8) {
                if isIndeterminate {
                    ProgressView()
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 320)
                } else {
                    ProgressView(value: progress)
                        .progressViewStyle(.linear)
                        .frame(maxWidth: 320)
                }

                if !isIndeterminate {
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }

            Spacer()
        }
        .padding(40)
        .frame(width: 440, height: 260)
    }
}

#Preview("Indeterminate") {
    ModelDownloadView(progress: 0)
}

#Preview("42%") {
    ModelDownloadView(progress: 0.42)
}
