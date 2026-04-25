// ============================================================
// MeetKaiView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "8. Meet Your Coach" (EU3Qg)
//
// Layout (top → bottom, padding 40 vertical / 24 horizontal):
//   - Status bar
//   - Concentric rings visualisation (200×200 frame, layout:none)
//       • Outer ring:  200×200, fzPrimary stroke 2pt
//       • Middle ring: 140×140, fzPrimary stroke 1.5pt (dim)
//       • Inner ring:   80×80,  fzCoral stroke 1pt
//       • Dot:          12×12,  fzPrimary fill, centred
//       • Glow:        120×120, purple radial gradient
//   - "Hi, I'm Kai.\nYour AI coach." (32pt, centred)
//   - Subtitle body text (centred, secondary)
//   - Profile summary card (YOUR PROFILE label + details)
//   - Spacer
//   - "Let's go" primary button
//
// Rings animate on appear (rotation + pulse).
// ============================================================

import SwiftUI

struct MeetKaiView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onLetsGo: () -> Void

    @State private var outerRotation: Double = 0
    @State private var middleRotation: Double = 0
    @State private var pulseScale: CGFloat = 1.0
    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(spacing: 32) {
                    // ── Kai Rings Visualisation ───────────────────
                    KaiRingsView(
                        outerRotation: outerRotation,
                        middleRotation: middleRotation,
                        pulseScale: pulseScale
                    )

                    // ── Text Block ────────────────────────────────
                    VStack(spacing: 16) {
                        Text("Hi, I'm Kai.\nYour AI coach.")
                            .font(.fzHeading(32, weight: .bold))
                            .foregroundStyle(Color.fzText)
                            .multilineTextAlignment(.center)

                        Text("I've studied your goals and fitness level. I'll build workouts that challenge you — and adapt as you grow stronger.")
                            .font(.fzBody(16))
                            .foregroundStyle(Color.fzTextSecondary)
                            .multilineTextAlignment(.center)
                            .lineSpacing(16 * 0.5)
                            .frame(maxWidth: .infinity)
                    }
                    .frame(maxWidth: .infinity)

                    // ── Profile Summary ───────────────────────────
                    ProfileSummaryCard(viewModel: viewModel)

                    Spacer()

                    // ── Let's Go ──────────────────────────────────
                    ForzeeButton(
                        title: "Let's go",
                        action: onLetsGo,
                        isLoading: viewModel.isSaving
                    )
                    .padding(.bottom, ForzeeSpacing.screenPadding)
                }
                .padding(.horizontal, ForzeeSpacing.screenPadding)
                .padding(.top, ForzeeSpacing.screenPadding)
                .opacity(contentOpacity)
            }
        }
        .onAppear {
            withAnimation(.easeIn(duration: 0.5)) {
                contentOpacity = 1
            }
            startRingAnimation()
        }
    }

    // MARK: - Ring Animation

    private func startRingAnimation() {
        // Slow continuous outer ring rotation
        withAnimation(.linear(duration: 12).repeatForever(autoreverses: false)) {
            outerRotation = 360
        }
        // Counter-rotation for middle ring
        withAnimation(.linear(duration: 8).repeatForever(autoreverses: false)) {
            middleRotation = -360
        }
        // Subtle pulse
        withAnimation(.easeInOut(duration: 2.5).repeatForever(autoreverses: true)) {
            pulseScale = 1.06
        }
    }
}

// MARK: - KaiRingsView

private struct KaiRingsView: View {
    let outerRotation: Double
    let middleRotation: Double
    let pulseScale: CGFloat

    var body: some View {
        ZStack {
            // Purple glow
            RadialGradient(
                colors: [Color(hex: "6C63FF").opacity(0.19), Color.clear],
                center: .center, startRadius: 0, endRadius: 60
            )
            .frame(width: 120, height: 120)

            // Outer ring — fzPrimary, 2pt stroke
            Circle()
                .strokeBorder(Color.fzPrimary, lineWidth: 2)
                .frame(width: 200, height: 200)
                .rotationEffect(.degrees(outerRotation))
                .scaleEffect(pulseScale)

            // Middle ring — fzPrimary dim, 1.5pt
            Circle()
                .strokeBorder(Color.fzPrimary.opacity(0.4), lineWidth: 1.5)
                .frame(width: 140, height: 140)
                .rotationEffect(.degrees(middleRotation))

            // Inner ring — fzCoral, 1pt
            Circle()
                .strokeBorder(Color.fzCoral, lineWidth: 1)
                .frame(width: 80, height: 80)

            // Centre dot — fzPrimary fill
            Circle()
                .fill(Color.fzPrimary)
                .frame(width: 12, height: 12)
        }
        .frame(width: 200, height: 200)
    }
}

// MARK: - ProfileSummaryCard

private struct ProfileSummaryCard: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("YOUR PROFILE")
                .font(.fzBody(11, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .tracking(1)

            Text(profileSummary)
                .font(.fzBody(14, weight: .medium))
                .foregroundStyle(Color.fzText)
                .lineSpacing(14 * 0.5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }

    private var profileSummary: String {
        let level = viewModel.fitnessLevel?.title ?? "Getting started"
        let days = viewModel.selectedDays.count
        let time = viewModel.preferredTime.label
        let goals = viewModel.selectedGoals.prefix(2).map(\.label).joined(separator: " · ")
        return "\(level) · \(days)x/week · \(time)s\n\(goals.isEmpty ? "Building healthy habits" : goals)"
    }
}

#Preview {
    MeetKaiView(onLetsGo: {})
        .environmentObject(OnboardingViewModel())
}
