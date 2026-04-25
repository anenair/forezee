// ============================================================
// OnboardingProgressBar.swift
// Forzee — Core/DesignSystem
//
// 5-segment stepped progress bar shown at the top of each
// onboarding step screen.
//
// Design spec (forezee.pen):
//   - 5 segments, gap 8, height 4, cornerRadius 2
//   - Active fill: fzPrimary
//   - Inactive fill: fzBorder (#2A2A3D)
//   - Animated on step change
// ============================================================

import SwiftUI

struct OnboardingProgressBar: View {

    /// The currently completed step count (1-based). E.g. step=1 → first bar active.
    let currentStep: Int
    let totalSteps: Int

    init(step: Int, total: Int = 5) {
        self.currentStep = step
        self.totalSteps = total
    }

    var body: some View {
        HStack(spacing: 8) {
            ForEach(1...totalSteps, id: \.self) { index in
                RoundedRectangle(cornerRadius: ForzeeRadius.progress)
                    .fill(index <= currentStep ? Color.fzPrimary : Color.fzBorder)
                    .frame(height: 4)
                    .animation(.easeInOut(duration: 0.3), value: currentStep)
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        OnboardingProgressBar(step: 1)
        OnboardingProgressBar(step: 3)
        OnboardingProgressBar(step: 5)
    }
    .padding(24)
    .background(Color.fzBg)
}
