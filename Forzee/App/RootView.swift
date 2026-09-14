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
                AuthFlowView()
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
