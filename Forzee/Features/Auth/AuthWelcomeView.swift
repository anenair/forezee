// ============================================================
// AuthWelcomeView.swift
// Forzee — Features/Auth
//
// Design reference: forezee.pen → "2. Onboarding Welcome" (v2Yku)
// (originally built for onboarding, moved here — it's the real
// entry point since auth gates onboarding, not the other way
// around: RootView shows AuthFlowView while !isAuthenticated)
//
// Layout (top → bottom):
//   - Status bar (system)
//   - Content area (fill, padding 40 vertical / 24 horizontal):
//       - Spacer
//       - Hero heading: "Your coach.\nYour pace.\nYour life."
//         SF Pro Display, 36pt bold, lineHeight 1.15
//       - Subtext: 16pt body, secondary, lineHeight 1.5
//       - Spacer (fill)
//       - "Get Started" primary button
//       - "I already have an account" text link
// ============================================================

import SwiftUI

struct AuthWelcomeView: View {

    let onGetStarted: () -> Void
    let onAlreadyHaveAccount: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar spacer (system handles the bar itself)
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Hero ────────────────────────────────────
                    VStack(alignment: .leading, spacing: 24) {
                        Text("Your coach.\nYour pace.\nYour life.")
                            .font(.fzHeading(36, weight: .bold))
                            .foregroundStyle(Color.fzText)
                            .lineSpacing(36 * 0.15) // lineHeight 1.15
                            .frame(maxWidth: .infinity, alignment: .leading)

                        Text("Forzee uses AI to build workouts that fit your body, your goals, and your schedule — then adapts as you grow.")
                            .font(.fzBody(16))
                            .foregroundStyle(Color.fzTextSecondary)
                            .lineSpacing(16 * 0.5) // lineHeight 1.5
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    Spacer()

                    // ── CTAs ────────────────────────────────────
                    VStack(spacing: 16) {
                        ForzeeButton(title: "Get Started", action: onGetStarted)

                        ForzeeTextButton(
                            title: "I already have an account",
                            action: onAlreadyHaveAccount
                        )
                    }
                }
                .padding(.horizontal, ForzeeSpacing.screenPadding)
                .padding(.top, ForzeeSpacing.screenPadding)
                .padding(.bottom, ForzeeSpacing.screenPadding)
                .frame(maxHeight: .infinity)
            }
        }
    }
}

#Preview {
    AuthWelcomeView(onGetStarted: {}, onAlreadyHaveAccount: {})
}
