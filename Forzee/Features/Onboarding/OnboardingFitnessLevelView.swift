// ============================================================
// OnboardingFitnessLevelView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "3. Onboarding Fitness Level" (FFMDG)
//
// Layout:
//   - Progress bar (1/5)
//   - "Step 1 of 5" label in fzPrimary
//   - "Where are you right now?" heading (28pt, bold)
//   - 4 option cards filling remaining height equally
//
// Interaction: tap a card → 200ms delay → auto-advance to next step.
// This is single-select — no Continue button needed.
//
// Card states:
//   Selected:   fzSurface fill, fzPrimary border (2pt), fzPrimary icon
//   Unselected: fzSurface fill, fzBorder (1pt), fzTextSecondary icon
// ============================================================

import SwiftUI

struct OnboardingFitnessLevelView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onSelect: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                // Status bar spacer
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Progress + Step Label ────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingProgressBar(step: 1)

                        Text("Step 1 of 5")
                            .font(.fzBody(13, weight: .medium))
                            .foregroundStyle(Color.fzPrimary)
                    }

                    // ── Heading ──────────────────────────────────
                    Text("Where are you\nright now?")
                        .font(.fzHeading(28, weight: .bold))
                        .foregroundStyle(Color.fzText)
                        .lineSpacing(28 * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── Option Cards ─────────────────────────────
                    VStack(spacing: 12) {
                        ForEach(FitnessLevel.allCases) { level in
                            FitnessLevelCard(
                                level: level,
                                isSelected: viewModel.fitnessLevel == level,
                                onTap: {
                                    viewModel.fitnessLevel = level
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

// MARK: - FitnessLevelCard

private struct FitnessLevelCard: View {

    let level: FitnessLevel
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 16) {
                Image(systemName: level.iconSystemName)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .foregroundStyle(isSelected ? Color.fzPrimary : Color.fzTextSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text(level.title)
                        .font(.fzBody(16, weight: .semibold))
                        .foregroundStyle(Color.fzText)

                    Text(level.subtitle)
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
    OnboardingFitnessLevelView(onSelect: {})
        .environmentObject(OnboardingViewModel())
}
