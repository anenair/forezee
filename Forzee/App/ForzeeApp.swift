// ============================================================
// ForzeeApp.swift
// Forzee
//
// App entry point. Bootstraps Supabase, RevenueCat, and the
// global AppState before handing off to the root view.
// ============================================================

import SwiftUI
import SwiftData

@main
struct ForzeeApp: App {

    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @StateObject private var appState = AppState()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Bootstrap third-party SDKs on first launch.
        // Order matters: Supabase first (auth), then RevenueCat (subscription).
        AppBootstrap.configure()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(appState)
        }
        .modelContainer(for: PendingWrite.self)
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Cancel-and-reschedule on every foreground: if the user doesn't
            // come back within the window, the re-engagement nudge fires.
            let coachMode = appState.userProfile?.coachMode ?? "guided"
            NotificationManager.shared.scheduleReengagementNudge(coachMode: coachMode)
            // Background sync is opportunistic, not per-save — app foreground
            // is one of its three triggers (the others: connectivity restored,
            // periodic timer while open). See SyncManager.
            Task { await SyncManager.shared.syncPendingWrites() }
        }
    }
}
