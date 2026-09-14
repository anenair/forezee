// ============================================================
// KaiRingsView.swift
// Forzee — Core/DesignSystem
//
// Kai's visual signature: sound-wave ripples pulsing outward
// from a breathing core, with a slow field of particles
// drifting around it — reads as "listening"/"thinking" rather
// than a generic spinner. Fully self-contained/self-animating.
//
// Used full-size (200pt) as the hero visual in MeetKaiView, and
// small (~32-40pt) as the "Kai is thinking" indicator in Coach
// chat and the daily briefing card.
// ============================================================

import SwiftUI

struct KaiRingsView: View {

    var size: CGFloat = 200

    private let particleCount = 9
    private let rippleCount = 3

    @State private var corePulse: CGFloat = 1.0
    @State private var coreGlowOpacity: Double = 0.55
    @State private var galaxyRotation: Double = 0
    @State private var starTwinkle: Double = 0.35
    @State private var rippleScales: [CGFloat] = Array(repeating: 0.32, count: 3)
    @State private var rippleOpacities: [Double] = Array(repeating: 0.5, count: 3)

    var body: some View {
        ZStack {
            // ── Galaxy — small particles drifting slowly around the core
            ForEach(0..<particleCount, id: \.self) { i in
                let angle = Double(i) / Double(particleCount) * 360
                let radius = size / 2 * (0.42 + 0.48 * Double(i % 3) / 2)
                let dotSize: CGFloat = max(1, size * (i % 4 == 0 ? 0.02 : 0.01))

                Circle()
                    .fill(i % 3 == 0 ? Color.fzCoral : Color.fzPrimary)
                    .frame(width: dotSize, height: dotSize)
                    .opacity(starTwinkle)
                    .offset(x: radius)
                    .rotationEffect(.degrees(angle + galaxyRotation))
            }

            // ── Sound waves — rings pulsing outward and fading, staggered
            ForEach(0..<rippleCount, id: \.self) { i in
                Circle()
                    .strokeBorder(Color.fzPrimary.opacity(rippleOpacities[i]), lineWidth: max(1, size * 0.0075))
                    .frame(width: size * rippleScales[i], height: size * rippleScales[i])
            }

            // ── Core — soft glow, breathing
            RadialGradient(
                colors: [Color.fzPrimary.opacity(coreGlowOpacity), Color(hex: "6C63FF").opacity(0.22), .clear],
                center: .center, startRadius: 0, endRadius: size * 0.35
            )
            .frame(width: size * 0.8, height: size * 0.8)
            .scaleEffect(corePulse)

            // ── Core dot — the "strong" anchor at the centre
            Circle()
                .fill(Color.fzPrimary)
                .frame(width: max(3, size * 0.06), height: max(3, size * 0.06))
                .scaleEffect(corePulse)
                .shadow(color: Color.fzPrimary.opacity(0.7), radius: size * 0.05)
        }
        .frame(width: size, height: size)
        .onAppear(perform: startAnimating)
    }

    private func startAnimating() {
        // Slow, majestic drift — the galaxy feel
        withAnimation(.linear(duration: 40).repeatForever(autoreverses: false)) {
            galaxyRotation = 360
        }
        // Slow breathing core
        withAnimation(.easeInOut(duration: 3).repeatForever(autoreverses: true)) {
            corePulse = 1.12
            coreGlowOpacity = 0.85
        }
        // Gentle star twinkle
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            starTwinkle = 0.9
        }
        // Sound-wave ripples, staggered so they read as continuous pulses
        for i in rippleScales.indices {
            let delay = Double(i) * (2.4 / Double(rippleCount))
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
                withAnimation(.easeOut(duration: 2.4).repeatForever(autoreverses: false)) {
                    rippleScales[i] = 1.05
                    rippleOpacities[i] = 0
                }
            }
        }
    }
}

#Preview {
    VStack(spacing: 40) {
        KaiRingsView()
        KaiRingsView(size: 40)
    }
    .frame(maxWidth: .infinity, maxHeight: .infinity)
    .forzeeBackground()
}
