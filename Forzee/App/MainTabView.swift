// ============================================================
// MainTabView.swift
// Forzee
//
// Root tab bar after auth + onboarding are complete.
// Tab structure mirrors the AppTab enum in AppState.
// ============================================================

import SwiftUI

struct MainTabView: View {

    @EnvironmentObject var appState: AppState

    var body: some View {
        TabView(selection: $appState.activeTab) {
            // ── Coach Tab ──────────────────────────────────────
            CoachView()
                .tabItem {
                    Label(AppTab.coach.title, systemImage: AppTab.coach.iconName)
                }
                .tag(AppTab.coach)

            // ── Workout Tab ────────────────────────────────────
            WorkoutTabView()
                .tabItem {
                    Label(AppTab.workout.title, systemImage: AppTab.workout.iconName)
                }
                .tag(AppTab.workout)

            // ── Progress Tab ───────────────────────────────────
            ProgressTabView()
                .tabItem {
                    Label(AppTab.progress.title, systemImage: AppTab.progress.iconName)
                }
                .tag(AppTab.progress)

            // ── Settings Tab ───────────────────────────────────
            SettingsView()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.iconName)
                }
                .tag(AppTab.settings)
        }
    }
}
