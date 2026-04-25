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
    }
}
