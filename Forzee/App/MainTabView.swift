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
            WorkoutPlaceholderView()
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

// MARK: - Workout Placeholder (replaced once Phase 1 workout UI lands)

private struct WorkoutPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Workout")
                .navigationTitle("Workout")
        }
    }
}
