// ============================================================
// SplashView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "1. Splash Screen" (LoUeh)
//
// Layout:
//   - Full-screen dark background (#0A0A0F)
//   - Radial glow ellipse (teal, 200×200, absolute positioned)
//   - "forzee" logotype: SF Pro Rounded, 48pt bold, letterSpacing -1
//   - "See the strength ahead." tagline: 16pt body, secondary text
//   - Gap 16 between logo and tagline
//   - Advances automatically after 2 seconds
// ============================================================

import SwiftUI

struct SplashView: View {

    let onComplete: () -> Void

    @State private var logoOpacity: Double = 0
    @State private var logoScale: Double = 0.92

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            // ── Radial glow — behind the text ─────────────────
            // Design: ellipse 200×200, radial gradient teal→transparent
            // Positioned at x:96, y:300 relative to 393pt screen
            RadialGradient(
                colors: [
                    Color(hex: "3D8B9C").opacity(0.31),
                    Color.clear
                ],
                center: .center,
                startRadius: 0,
                endRadius: 100
            )
            .frame(width: 200, height: 200)
            .offset(x: -0.5, y: 55) // Centred slightly below midpoint
            .allowsHitTesting(false)

            // ── Logo + tagline ────────────────────────────────
            VStack(spacing: 16) {
                Text("forzee")
                    .font(.fzDisplay(48, weight: .bold))
                    .foregroundStyle(Color.fzText)
                    .tracking(-1)

                Text("See the strength ahead.")
                    .font(.fzBody(16))
                    .foregroundStyle(Color.fzTextSecondary)
            }
            .opacity(logoOpacity)
            .scaleEffect(logoScale)
        }
        .onAppear {
            // Fade + scale in
            withAnimation(.easeOut(duration: 0.6)) {
                logoOpacity = 1
                logoScale = 1.0
            }
            // Auto-advance after 2.2s
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
                onComplete()
            }
        }
    }
}

#Preview {
    SplashView(onComplete: {})
}
