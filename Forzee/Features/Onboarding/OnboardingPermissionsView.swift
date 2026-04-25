// ============================================================
// OnboardingPermissionsView.swift
// Forzee — Features/Onboarding
//
// Design reference: forezee.pen → "7. Onboarding Permissions" (gTChZ)
//
// Layout:
//   - "Forzee works best with access to:" heading (28pt)
//   - 4 permission rows with toggles:
//       1. Apple Health   (coral heart-pulse icon) — toggle default ON
//       2. Sleep Data     (primary moon icon)       — toggle default ON
//       3. Calendar       (primary calendar icon)   — toggle default OFF
//       4. Location       (primary map-pin icon)    — toggle default OFF
//   - Spacer (fill)
//   - "Grant All" primary button
//   - "Set up later" text link
//
// Tapping "Grant All" requests system permissions via HealthKit /
// EventKit / CoreLocation. Actual permission request handlers are
// TODO — stubbed here for the UI flow.
// ============================================================

import SwiftUI

struct OnboardingPermissionsView: View {

    @EnvironmentObject private var viewModel: OnboardingViewModel
    let onGrantAll: () -> Void
    let onSetUpLater: () -> Void
    let onBack: () -> Void

    var body: some View {
        ZStack {
            Color.fzBg.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer().frame(height: 62)

                VStack(alignment: .leading, spacing: 24) {
                    // ── Heading ───────────────────────────────────
                    Text("Forzee works best\nwith access to:")
                        .font(.fzHeading(28, weight: .bold))
                        .foregroundStyle(Color.fzText)
                        .lineSpacing(28 * 0.2)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    // ── Permission Rows ───────────────────────────
                    VStack(spacing: 12) {
                        PermissionRow(
                            iconName: "heart.fill",
                            iconColor: Color.fzCoral,
                            title: "Apple Health",
                            subtitle: "Sync workouts, heart rate & steps",
                            isOn: $viewModel.healthKitGranted
                        )
                        PermissionRow(
                            iconName: "moon.fill",
                            iconColor: Color.fzPrimary,
                            title: "Sleep Data",
                            subtitle: "Optimize recovery recommendations",
                            isOn: $viewModel.sleepDataGranted
                        )
                        PermissionRow(
                            iconName: "calendar",
                            iconColor: Color.fzPrimary,
                            title: "Calendar",
                            subtitle: "Schedule workouts around your day",
                            isOn: $viewModel.calendarGranted
                        )
                        PermissionRow(
                            iconName: "location.fill",
                            iconColor: Color.fzPrimary,
                            title: "Location",
                            subtitle: "Find gyms and outdoor routes nearby",
                            isOn: $viewModel.locationGranted
                        )
                    }
                    .frame(maxHeight: .infinity)

                    // ── CTAs ──────────────────────────────────────
                    VStack(spacing: 12) {
                        ForzeeButton(title: "Grant All") {
                            grantAll()
                        }
                        ForzeeTextButton(title: "Set up later", action: onSetUpLater)
                    }
                    .padding(.bottom, ForzeeSpacing.screenPadding)
                }
                .padding(.horizontal, ForzeeSpacing.screenPadding)
                .padding(.top, ForzeeSpacing.screenPadding)
            }
        }
    }

    private func grantAll() {
        // TODO: Request actual system permissions via HealthKit, EventKit, CoreLocation
        // For now, set all toggles on and advance
        viewModel.healthKitGranted = true
        viewModel.sleepDataGranted = true
        viewModel.calendarGranted = true
        viewModel.locationGranted = true
        onGrantAll()
    }
}

// MARK: - PermissionRow

private struct PermissionRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let subtitle: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: iconName)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(iconColor)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.fzBody(15, weight: .semibold))
                    .foregroundStyle(Color.fzText)

                Text(subtitle)
                    .font(.fzBody(13))
                    .foregroundStyle(Color.fzTextSecondary)
            }

            Spacer()

            Toggle("", isOn: $isOn)
                .toggleStyle(ForzeeToggleStyle())
                .labelsHidden()
        }
        .padding(20)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }
}

// MARK: - ForzeeToggleStyle

/// Custom toggle using fzPrimary accent for the ON state.
struct ForzeeToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        RoundedRectangle(cornerRadius: 14)
            .fill(configuration.isOn ? Color.fzPrimary : Color.fzBorder)
            .frame(width: 48, height: 28)
            .overlay(
                Circle()
                    .fill(Color.white)
                    .frame(width: 22, height: 22)
                    .offset(x: configuration.isOn ? 10 : -10)
                    .animation(.spring(response: 0.3, dampingFraction: 0.75), value: configuration.isOn)
            )
            .onTapGesture {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                configuration.isOn.toggle()
            }
    }
}

#Preview {
    OnboardingPermissionsView(onGrantAll: {}, onSetUpLater: {}, onBack: {})
        .environmentObject(OnboardingViewModel())
}
