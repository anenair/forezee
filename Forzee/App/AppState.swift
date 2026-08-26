// ============================================================
// AppState.swift
// Forzee
//
// Central application state. Injected into the view hierarchy
// via @EnvironmentObject. Owns the auth session, subscription
// tier, and navigation routing decisions.
//
// Rules:
//   - All mutations must happen on @MainActor
//   - Business logic lives in dedicated services, not here
//   - This file drives navigation only — no AI or data logic
// ============================================================

import SwiftUI
import Combine

@MainActor
final class AppState: ObservableObject {

    // MARK: - Shared Reference

    /// Weak reference to the live instance so singleton services (PurchaseManager,
    /// etc.) can push updates without being threaded through the view hierarchy.
    /// Set once in `init()` — there is only ever one AppState per app run.
    static private(set) weak var shared: AppState?

    // MARK: - Auth

    /// Whether the user has an active, verified Supabase session.
    @Published var isAuthenticated: Bool = false

    /// The authenticated Supabase user ID (UUID string).
    @Published var userId: String? = nil

    // MARK: - Onboarding

    /// True once the user has completed the full onboarding flow.
    /// Persisted in UserDefaults and confirmed against `profiles.onboarding_complete`.
    @Published var onboardingComplete: Bool = false

    // MARK: - Profile

    /// The loaded user profile from Supabase `profiles` table.
    @Published var userProfile: UserProfile? = nil

    // MARK: - Subscription

    /// The user's current subscription tier (free or premium).
    /// Sourced from RevenueCat, reflected in `profiles.subscription_tier`.
    @Published var subscriptionTier: SubscriptionTier = .free

    // MARK: - Navigation

    /// The currently active root tab.
    @Published var activeTab: AppTab = .coach

    // MARK: - Init

    init() {
        Self.shared = self
        restoreSession()
    }

    // MARK: - Session Restoration

    /// Attempts to restore an existing Supabase auth session on launch.
    /// Called once at init. Sets `isAuthenticated` and loads the user profile.
    private func restoreSession() {
        Task {
            await ForzeeDataService.shared.restoreSession { [weak self] userId in
                guard let self else { return }
                if let userId {
                    self.userId = userId
                    self.isAuthenticated = true
                    await self.loadProfile(userId: userId)
                }
            }
        }
    }

    /// Loads the user profile from Supabase and sets `onboardingComplete`.
    private func loadProfile(userId: String) async {
        do {
            let profile = try await ForzeeDataService.shared.fetchProfile(userId: userId)
            self.userProfile = profile
            self.onboardingComplete = profile.onboardingComplete
            self.subscriptionTier = profile.subscriptionTier
        } catch {
            // Profile may not exist yet for brand-new users — that's fine.
            // Onboarding flow will create it.
            #if DEBUG
            print("AppState: profile not found or error loading — \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Sign Out

    func signOut() async {
        await ForzeeDataService.shared.signOut()
        isAuthenticated = false
        userId = nil
        userProfile = nil
        onboardingComplete = false
        subscriptionTier = .free
        activeTab = .coach
    }
}

// MARK: - AppTab

/// The root-level navigation tabs.
enum AppTab: String, CaseIterable {
    case coach    = "coach"
    case workout  = "workout"
    case progress = "progress"
    case settings = "settings"

    var title: String {
        switch self {
        case .coach:    return "Coach"
        case .workout:  return "Workout"
        case .progress: return "Progress"
        case .settings: return "Settings"
        }
    }

    var iconName: String {
        switch self {
        case .coach:    return "message.fill"
        case .workout:  return "dumbbell.fill"
        case .progress: return "chart.bar.fill"
        case .settings: return "gearshape.fill"
        }
    }
}
