// ============================================================
// MeetKaiView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "8. Meet Your Coach" (EU3Qg)
//
// Layout (top → bottom, padding 40 vertical / 24 horizontal):
//   - Status bar
//   - Kai visualisation (200×200 frame): a breathing core glow,
//     sound-wave ripples pulsing outward and fading, and a slow
//     drifting field of small particles orbiting it — soothing,
//     continuous motion with a strong, solid centre. See KaiRingsView.
//   - "Hi, I'm Kai.\nYour AI coach." (32pt, centred)
//   - Subtitle body text (centred, secondary)
//   - Profile summary card (YOUR PROFILE label + details)
//   - Spacer
//   - "Let's go" primary button
// ============================================================

import SwiftUI

struct MeetKaiView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onLetsGo: () -> Void

    @State private var contentOpacity: Double = 0

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(spacing: 32) {
                    // ── Kai Visualisation ─────────────────────────
                    KaiRingsView()

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
        }
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
