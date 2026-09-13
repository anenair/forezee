// ============================================================
// UserProfile.swift
// Forzee — Core/Models
//
// Maps to the `profiles` table in Supabase.
// This is the source of truth for user identity and fitness
// context used by Kai on every coaching call.
// ============================================================

import Foundation

struct UserProfile: Identifiable, Codable, Equatable {

    // MARK: - Identity (mirrors Supabase profiles table)

    let id: String                    // UUID — matches auth.users.id
    var fullName: String?
    var avatarUrl: String?

    // MARK: - Fitness Context

    /// The user's fitness level. Drives Kai's tone and programming complexity.
    var fitnessLevel: String          // novice | returning | intermediate | advanced

    /// The user's goals. Used by Kai for workout and advice personalisation.
    var goals: [String]               // e.g. ["build_muscle", "lose_weight"]

    /// Available equipment. Kai uses this to constrain exercise selection.
    var equipment: [String]           // e.g. ["full_gym"] | ["bodyweight", "dumbbells"]

    /// Preferred workout days.
    var preferredDays: [String]       // e.g. ["monday", "wednesday", "friday"]

    /// How much Kai initiates contact. advisory | guided | accountability
    var coachMode: String

    /// Preferred session duration in minutes.
    var preferredDurationMins: Int

    /// Any injuries or physical limitations (free text).
    /// Fed directly to Kai's context snapshot.
    var limitations: String?

    // MARK: - App State

    /// True once the user has completed the full onboarding flow.
    var onboardingComplete: Bool

    // MARK: - Subscription

    var subscriptionTier: SubscriptionTier
    var subscriptionExpiresAt: Date?

    // MARK: - Timestamps

    let createdAt: Date
    var updatedAt: Date

    // MARK: - Coding Keys (snake_case to camelCase mapping)

    enum CodingKeys: String, CodingKey {
        case id
        case fullName              = "full_name"
        case avatarUrl             = "avatar_url"
        case fitnessLevel          = "fitness_level"
        case goals
        case equipment
        case preferredDays         = "preferred_days"
        case coachMode             = "coach_mode"
        case preferredDurationMins = "preferred_duration_mins"
        case limitations
        case onboardingComplete    = "onboarding_complete"
        case subscriptionTier      = "subscription_tier"
        case subscriptionExpiresAt = "subscription_expires_at"
        case createdAt             = "created_at"
        case updatedAt             = "updated_at"
    }
}

// MARK: - Convenience

extension UserProfile {

    /// A new blank profile for a freshly registered user.
    static func new(userId: String) -> UserProfile {
        UserProfile(
            id: userId,
            fullName: nil,
            avatarUrl: nil,
            fitnessLevel: "novice",
            goals: [],
            equipment: ["bodyweight"],
            preferredDays: [],
            coachMode: "guided",
            preferredDurationMins: 45,
            limitations: nil,
            onboardingComplete: false,
            subscriptionTier: .free,
            subscriptionExpiresAt: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
