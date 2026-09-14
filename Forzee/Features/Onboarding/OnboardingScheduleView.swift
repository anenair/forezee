// ============================================================
// OnboardingScheduleView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "6. Onboarding Schedule" (SpAlt)
//
// Layout:
//   - Progress bar (4/5)
//   - "Step 4 of 5" label
//   - "When do you like to train?" heading
//   - "TRAINING DAYS" section label (caps, 11pt, letter-spacing 1)
//   - Day picker row: M T W T F S S (44pt circles)
//   - "PREFERRED TIME" section label
//   - Segmented: Morning / Afternoon / Evening
//   - Session length card ("About 45 minutes")
//   - "Continue" button
//
// Day circle states:
//   Selected: fzPrimary fill, dark text (#0A0A0F)
//   Unselected: fzSurface fill, fzBorder stroke, white text
// ============================================================

import SwiftUI

struct OnboardingScheduleView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onContinue: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        // ── Progress + Step ──────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            OnboardingProgressBar(step: 4)
                            Text("Step 4 of 5")
                                .font(.fzBody(13, weight: .medium))
                                .foregroundStyle(Color.fzPrimary)
                        }

                        // ── Heading ──────────────────────────────
                        Text("When do you like\nto train?")
                            .font(.fzHeading(28, weight: .bold))
                            .foregroundStyle(Color.fzText)
                            .lineSpacing(28 * 0.2)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        // ── Training Days ─────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("TRAINING DAYS")
                                .font(.fzBody(11, weight: .semibold))
                                .foregroundStyle(Color.fzTextSecondary)
                                .tracking(1)

                            HStack(spacing: 8) {
                                ForEach(Weekday.allCases) { day in
                                    DayCircle(
                                        day: day,
                                        isSelected: viewModel.selectedDays.contains(day),
                                        onTap: { toggleDay(day) }
                                    )
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }

                        // ── Preferred Time ────────────────────────
                        VStack(alignment: .leading, spacing: 12) {
                            Text("PREFERRED TIME")
                                .font(.fzBody(11, weight: .semibold))
                                .foregroundStyle(Color.fzTextSecondary)
                                .tracking(1)

                            TimeSegmentedControl(selected: $viewModel.preferredTime)
                        }

                        // ── Session Length ────────────────────────
                        VStack(alignment: .center, spacing: 12) {
                            Text("SESSION LENGTH")
                                .font(.fzBody(11, weight: .semibold))
                                .foregroundStyle(Color.fzTextSecondary)
                                .tracking(1)

                            Text("About \(viewModel.sessionLengthMinutes) minutes")
                                .font(.fzHeading(24, weight: .bold))
                                .foregroundStyle(Color.fzText)

                            SessionLengthSegmentedControl(selected: $viewModel.sessionLengthMinutes)

                            Text("Kai keeps workouts to this length — adjust anytime in Settings")
                                .font(.fzBody(13))
                                .foregroundStyle(Color.fzTextSecondary)
                                .multilineTextAlignment(.center)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(24)
                        .background(Color.fzSurface)
                        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
                        .overlay(
                            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                                .strokeBorder(Color.fzBorder, lineWidth: 1)
                        )

                        // ── Continue ──────────────────────────────
                        ForzeeButton(
                            title: "Continue",
                            action: onContinue,
                            isDisabled: !viewModel.canContinueFromSchedule
                        )
                        .padding(.bottom, ForzeeSpacing.screenPadding)
                    }
                    .padding(.horizontal, ForzeeSpacing.screenPadding)
                    .padding(.top, ForzeeSpacing.screenPadding)
                }
            }
        }
    }

    private func toggleDay(_ day: Weekday) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if viewModel.selectedDays.contains(day) {
            // Don't allow deselecting all days
            if viewModel.selectedDays.count > 1 {
                viewModel.selectedDays.remove(day)
            }
        } else {
            viewModel.selectedDays.insert(day)
        }
    }
}

// MARK: - DayCircle

private struct DayCircle: View {
    let day: Weekday
    let isSelected: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            Text(day.short)
                .font(.fzHeading(14, weight: .semibold))
                .foregroundStyle(isSelected ? Color(hex: "0A0A0F") : Color.fzText)
                .frame(maxWidth: .infinity)
                .frame(height: 44)
                .background(isSelected ? Color.fzPrimary : Color.fzSurface)
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .strokeBorder(isSelected ? Color.clear : Color.fzBorder, lineWidth: 1)
                )
                .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - TimeSegmentedControl

private struct TimeSegmentedControl: View {
    @Binding var selected: TimeOfDay

    var body: some View {
        HStack(spacing: 4) {
            ForEach(TimeOfDay.allCases) { time in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selected = time }
                }) {
                    Text(time.label)
                        .font(.fzBody(13, weight: .medium))
                        .foregroundStyle(selected == time ? Color(hex: "0A0A0F") : Color.fzTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                                .fill(selected == time ? Color.fzPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(height: 44)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.button))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.button)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

// MARK: - SessionLengthSegmentedControl

private struct SessionLengthSegmentedControl: View {
    @Binding var selected: Int

    private static let presets = [20, 30, 45, 60]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Self.presets, id: \.self) { minutes in
                Button(action: {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeInOut(duration: 0.2)) { selected = minutes }
                }) {
                    Text("\(minutes)")
                        .font(.fzBody(13, weight: .medium))
                        .foregroundStyle(selected == minutes ? Color(hex: "0A0A0F") : Color.fzTextSecondary)
                        .frame(maxWidth: .infinity)
                        .frame(maxHeight: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: ForzeeRadius.chip)
                                .fill(selected == minutes ? Color.fzPrimary : Color.clear)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .frame(height: 44)
        .background(Color.fzBg)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.button))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.button)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

#Preview {
    OnboardingScheduleView(onContinue: {})
        .environmentObject(OnboardingViewModel())
}
