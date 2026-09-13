// ============================================================
// SettingsView.swift
// Forzee — Features/Settings
//
// Phase 2: subscription status + upgrade entry point, Phase 2
// integration status (Health/Calendar/Location), and sign out.
// Replaces the Settings tab placeholder.
// ============================================================

import SwiftUI

struct SettingsView: View {

    @EnvironmentObject private var appState: AppState
    @ObservedObject private var healthKit = HealthKitManager.shared
    @ObservedObject private var calendar = CalendarManager.shared
    @ObservedObject private var weather = WeatherManager.shared
    @ObservedObject private var notifications = NotificationManager.shared

    @State private var showPaywall = false
    @State private var isSigningOut = false
    @State private var coachMode: CoachMode = .guided

    var body: some View {
        NavigationStack {
            ZStack {
                Color.fzBg.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: ForzeeSpacing.sectionGap) {
                        subscriptionCard
                        coachModeCard
                        integrationsCard
                        signOutButton
                    }
                    .padding(ForzeeSpacing.screenPadding)
                }
            }
            .navigationTitle("Settings")
            .task {
                await PurchaseManager.shared.refreshCustomerInfo(userId: appState.userId)
                await NotificationManager.shared.refreshAuthorizationStatus()
                if let saved = appState.userProfile?.coachMode, let mode = CoachMode(rawValue: saved) {
                    coachMode = mode
                }
            }
            .sheet(isPresented: $showPaywall) {
                PaywallView()
            }
        }
    }

    // MARK: - Subscription

    private var subscriptionCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(appState.subscriptionTier.displayName)
                        .font(.fzBody(16, weight: .semibold))
                        .foregroundStyle(Color.fzText)
                    Text(appState.subscriptionTier.isPremium
                         ? "Unlimited coaching & full context awareness"
                         : "3 messages/day, 1 workout/week")
                        .font(.fzBody(13))
                        .foregroundStyle(Color.fzTextSecondary)
                }
                Spacer()
                if appState.subscriptionTier.isPremium {
                    Image(systemName: "crown.fill").foregroundStyle(Color.fzPrimary)
                }
            }

            if appState.subscriptionTier.isFree {
                ForzeeButton(title: "Upgrade to Premium") { showPaywall = true }
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }

    // MARK: - Coach Mode

    private var coachModeCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("How Kai Reaches Out")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            VStack(spacing: 8) {
                ForEach(CoachMode.allCases) { mode in
                    Button {
                        coachMode = mode
                        Task { await saveCoachMode(mode) }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(mode.title)
                                    .font(.fzBody(14, weight: .semibold))
                                    .foregroundStyle(Color.fzText)
                                Text(mode.subtitle)
                                    .font(.fzBody(12))
                                    .foregroundStyle(Color.fzTextSecondary)
                            }
                            Spacer()
                            Image(systemName: coachMode == mode ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(coachMode == mode ? Color.fzPrimary : Color.fzBorder)
                        }
                        .padding(12)
                        .background(Color.fzSurfaceElevated)
                        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.chip))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }

    private func saveCoachMode(_ mode: CoachMode) async {
        guard let userId = appState.userId else { return }
        try? await ForzeeDataService.shared.updateProfile(["coach_mode": mode.rawValue], userId: userId)
        appState.userProfile?.coachMode = mode.rawValue
    }

    // MARK: - Integrations

    private var integrationsCard: some View {
        VStack(alignment: .leading, spacing: ForzeeSpacing.itemGap) {
            Text("Life Signals")
                .font(.fzBody(13, weight: .semibold))
                .foregroundStyle(Color.fzTextSecondary)
                .textCase(.uppercase)

            IntegrationRow(iconName: "heart.fill", iconColor: .fzCoral, title: "Apple Health", isOn: healthKit.isAuthorized) {
                Task { await HealthKitManager.shared.requestAuthorization() }
            }
            IntegrationRow(iconName: "calendar", iconColor: .fzPrimary, title: "Calendar", isOn: calendar.isAuthorized) {
                Task { await CalendarManager.shared.requestAccess() }
            }
            IntegrationRow(iconName: "location.fill", iconColor: .fzPrimary, title: "Weather & Location", isOn: weather.isAuthorized) {
                WeatherManager.shared.requestAuthorization()
            }
            IntegrationRow(iconName: "bell.fill", iconColor: .fzPrimary, title: "Notifications", isOn: notifications.isAuthorized) {
                Task {
                    guard await NotificationManager.shared.requestAuthorization() else { return }
                    // Onboarding doesn't persist preferred time-of-day, so a day picked
                    // here without onboarding's context defaults reminders to morning.
                    if let days = appState.userProfile?.preferredDays {
                        let weekdays = Set(days.compactMap(Weekday.init(rawValue:)))
                        NotificationManager.shared.scheduleWorkoutReminders(days: weekdays, time: .morning)
                    }
                }
            }
        }
        .padding(ForzeeSpacing.cardPadding)
        .background(Color.fzSurface)
        .clipShape(RoundedRectangle(cornerRadius: ForzeeRadius.card))
        .overlay(
            RoundedRectangle(cornerRadius: ForzeeRadius.card)
                .strokeBorder(Color.fzBorder, lineWidth: 1)
        )
    }

    // MARK: - Sign Out

    private var signOutButton: some View {
        Button {
            Task {
                isSigningOut = true
                await appState.signOut()
                isSigningOut = false
            }
        } label: {
            Text("Sign Out")
                .font(.fzBody(15, weight: .semibold))
                .foregroundStyle(Color.fzPink)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
        }
        .disabled(isSigningOut)
    }
}

// MARK: - IntegrationRow

private struct IntegrationRow: View {
    let iconName: String
    let iconColor: Color
    let title: String
    let isOn: Bool
    let onEnable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 20)
            Text(title)
                .font(.fzBody(14))
                .foregroundStyle(Color.fzText)
            Spacer()
            if isOn {
                Text("Connected")
                    .font(.fzBody(12, weight: .medium))
                    .foregroundStyle(Color.fzGreen)
            } else {
                Button("Connect", action: onEnable)
                    .font(.fzBody(12, weight: .medium))
                    .foregroundStyle(Color.fzPrimary)
            }
        }
    }
}

#Preview {
    SettingsView()
        .environmentObject(AppState())
}
