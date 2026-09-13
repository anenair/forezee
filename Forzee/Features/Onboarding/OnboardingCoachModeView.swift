// ============================================================
// OnboardingCoachModeView.swift
// Forzee — Features/Onboarding
//
// Step 5 of 5 — how much Kai should initiate contact. This is
// the "Tesla FSD levels, but for your coach" idea: an axis
// independent of fitness level (which drives tone/complexity).
// This one drives how proactive Kai is about reaching out.
//
// Same interaction pattern as OnboardingFitnessLevelView:
// single-select card list, tap → 200ms delay → auto-advance.
// ============================================================

import SwiftUI

struct OnboardingCoachModeView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Progress + Step Label ────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingProgressBar(step: 5)

                        Text("Step 5 of 5")
                            .font(.fzBody(13, weight: .medium))
                            .foregroundStyle(Color.fzPrimary)
                    }

                    // ── Heading ──────────────────────────────────
                    Text("How much should\nKai reach out?")
                        .font(.fzHeading(28, weight: .bold))
                        .foregroundStyle(Color.fzText)
                        .lineSpacing(28 * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("You can change this any time in Settings.")
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)

                    // ── Option Cards ─────────────────────────────
                    VStack(spacing: 12) {
                        ForEach(CoachMode.allCases) { mode in
                            CoachModeCard(
                                mode: mode,
                                isSelected: viewModel.coachMode == mode,
                                onTap: {
                                    viewModel.coachMode = mode
                                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                        onSelect()
                                    }
                                }
                            )
                        }
                    }
                    .frame(maxHeight: .infinity)
                }
                .padding(ForzeeSpacing.screenPadding)
            }
        }
    }
}

// MARK: - CoachModeCard

private struct CoachModeCard: View {

    let mode: CoachMode
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: mode.iconSystemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzTextSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(mode.title)
                        .font(.fzBody(16, weight: .semibold))
                        .foregroundStyle(Color.fzText)

                    Text(mode.subtitle)
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }

                Spacer()
            }
            .padding(20)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color.fzSurface)
            .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
            .overlay(
                RoundedRectangle(cornerRadius: ForzeeRadius.card)
                    .strokeBorder(
                        isSelected ? Color.fzPrimary : Color.fzBorder,
                        lineWidth: isSelected ? 2 : 1
                    )
            )
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingCoachModeView(onSelect: {})
        .environmentObject(OnboardingViewModel())
}
