// ============================================================
// OnboardingGoalsView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "4. Onboarding Goals" (dCHvO)
//
// Layout:
//   - Progress bar (2/5)
//   - "Step 2 of 5" label
//   - "What are you training for?" heading (28pt)
//   - 4 rows × 2 pill chips (multi-select)
//   - Spacer
//   - "Continue" primary button (enabled when ≥1 goal selected)
//
// Pill states:
//   Selected:   fzPrimary fill, no border, dark text
//   Unselected: fzSurface fill, fzBorder stroke, secondary text
//
// Note: Continue button is implied by the design (not shown in
// forezee.pen due to viewport truncation in the .pen file).
// ============================================================

import SwiftUI

struct OnboardingGoalsView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Progress + Step Label ────────────────────
                    VStack(alignment: .leading, spacing: 12) {
                        OnboardingProgressBar(step: 2)
                        Text("Step 2 of 5")
                            .font(.fzBody(13, weight: .medium))
                            .foregroundStyle(Color.fzPrimary)
                    }

                    // ── Heading ──────────────────────────────────
                    Text("What are you\ntraining for?")
                        .font(.fzHeading(28, weight: .bold))
                        .foregroundStyle(Color.fzText)
                        .lineSpacing(28 * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── Pill Grid ─────────────────────────────────
                    VStack(spacing: 10) {
                        ForEach(TrainingGoal.displayOrder, id: \.self) { row in
                            HStack(spacing: 10) {
                                ForEach(row) { goal in
                                    GoalPill(
                                        goal: goal,
                                        isSelected: viewModel.selectedGoals.contains(goal),
                                        onTap: { toggleGoal(goal) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }

                    Spacer()

                    // ── Continue ────────────────────────────────
                    ForzeeButton(
                        title: "Continue",
                        action: onContinue,
                        isDisabled: !viewModel.canContinueFromGoals
                    )
                    .padding(.bottom, ForzeeSpacing.screenPadding)
                }
                .padding(.horizontal, ForzeeSpacing.screenPadding)
                .padding(.top, ForzeeSpacing.screenPadding)
            }
        }
    }

    private func toggleGoal(_ goal: TrainingGoal) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if viewModel.selectedGoals.contains(goal) {
            viewModel.selectedGoals.remove(goal)
        } else {
            viewModel.selectedGoals.insert(goal)
        }
    }
}

// MARK: - GoalPill

private struct GoalPill: View {

    let goal: TrainingGoal
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(goal.label)
                .font(.fzBody(14, weight: .medium))
                .foregroundStyle(isSelected ? Color(hex: "0A0A0F") : Color.fzText)
                .padding(.horizontal, 18)
                .padding(.vertical, 10)
                .frame(maxWidth: .infinity)
                .background(
                    Capsule()
                        .fill(isSelected ? Color.fzPrimary : Color.fzSurface)
                )
                .overlay(
                    Capsule()
                        .strokeBorder(
                            isSelected ? Color.clear : Color.fzBorder,
                            lineWidth: 1
                        )
                )
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingGoalsView(onContinue: {})
        .environmentObject(OnboardingViewModel())
}
