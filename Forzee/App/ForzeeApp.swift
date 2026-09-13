// ============================================================
// ForzeeApp.swift
// Forzee
//
// App entry point. Bootstraps Supabase, RevenueCat, and the
// global AppState before handing off to the root view.
// ============================================================

import SwiftUI

@main
struct ForzeeApp: App {

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
        .onChange(of: scenePhase) { _, newPhase in
            guard newPhase == .active else { return }
            // Cancel-and-reschedule on every foreground: if the user doesn't
            // come back within the window, the re-engagement nudge fires.
            let coachMode = appState.userProfile?.coachMode ?? "guided"
            NotificationManager.shared.scheduleReengagementNudge(coachMode: coachMode)
        }
    }
}
