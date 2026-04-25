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
            CoachPlaceholderView()
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
            ProgressPlaceholderView()
                .tabItem {
                    Label(AppTab.progress.title, systemImage: AppTab.progress.iconName)
                }
                .tag(AppTab.progress)

            // ── Settings Tab ───────────────────────────────────
            SettingsPlaceholderView()
                .tabItem {
                    Label(AppTab.settings.title, systemImage: AppTab.settings.iconName)
                }
                .tag(AppTab.settings)
        }
    }
}

// MARK: - Tab Placeholders (replaced screen by screen as .pen diagrams land)

private struct CoachPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Kai Coach Interface")
                .navigationTitle("Coach")
        }
    }
}

private struct WorkoutPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Workout")
                .navigationTitle("Workout")
        }
    }
}

private struct ProgressPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Progress")
                .navigationTitle("Progress")
        }
    }
}

private struct SettingsPlaceholderView: View {
    var body: some View {
        NavigationStack {
            Text("Settings")
                .navigationTitle("Settings")
        }
    }
}
