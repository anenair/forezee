// ============================================================
// RootView.swift
// Forzee
//
// Root routing view. Decides which top-level experience to
// show based on AppState: auth gate → onboarding → main app.
// ============================================================

import SwiftUI
import SwiftData

struct RootView: View {

    @EnvironmentObject var appState: AppState
    @Environment(\.modelContext) private var modelContext

    /// Safety-net sync while the app is open — connectivity-restored and
    /// app-foreground (ForzeeApp) are the other two triggers. None of
    /// these run synchronously off an individual save.
    private let periodicSyncInterval: TimeInterval = 60

    var body: some View {
        Group {
            if !appState.isAuthenticated {
                // TODO: Replace with AuthView once designed + implemented
                AuthPlaceholderView()
            } else if !appState.onboardingComplete {
                OnboardingFlowView()
            } else {
                MainTabView()
            }
        }
        .animation(.easeInOut(duration: 0.3), value: appState.isAuthenticated)
        .animation(.easeInOut(duration: 0.3), value: appState.onboardingComplete)
        .task {
            SyncManager.shared.configure(modelContext: modelContext)
        }
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(periodicSyncInterval))
                await SyncManager.shared.syncPendingWrites()
            }
        }
    }
}

// MARK: - Placeholders (removed once real screens are implemented)

private struct AuthPlaceholderView: View {
    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 56))
                .foregroundStyle(.primary)
            Text("Forzee")
                .font(.largeTitle.bold())
            Text("Auth screen coming soon.")
                .foregroundStyle(.secondary)
        }
    }
}
