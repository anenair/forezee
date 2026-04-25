// ============================================================
// RootView.swift
// Forzee
//
// Root routing view. Decides which top-level experience to
// show based on AppState: auth gate → onboarding → main app.
// ============================================================

import SwiftUI

struct RootView: View {

    @EnvironmentObject var appState: AppState

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
