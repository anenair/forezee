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

    // MARK: - Training Preferences (roadmap Phase 4 "My Plan")
    //
    // Onboarding never asks about these — they only exist because "My Plan"
    // in Settings does. Sensible defaults come from UserProfile.new() below,
    // same as every other field here being editable anytime rather than
    // frozen at signup.

    /// full_body | upper_lower | push_pull_legs | body_part_split | let_kai_decide
    var trainingSplit: String
    /// low | moderate | high — how much Kai varies exercise selection week to week.
    var exerciseVariability: String
    /// Whether Kai should prescribe warm-up sets before working sets.
    var warmupSetsEnabled: Bool
    /// Whether Kai may structure exercises as circuits/supersets, not just sequential.
    var circuitsSupersetsEnabled: Bool
    /// lbs | kg — which unit the user thinks in. Doesn't change how weight is
    /// stored (always kg internally, see WorkoutExercise.weightKg) — this is
    /// a display/phrasing preference only.
    var weightUnit: String
    /// monday | sunday
    var startOfWeek: String

    // MARK: - Personal Profile ("About You" — a separate settings screen,
    // not part of onboarding)
    //
    // Everything here is optional and nil by default — unlike the training
    // preferences above, there's no sane universal default for someone's
    // birth date or weight. Kai treats a nil field as "not provided," never
    // guesses one. Auto-calculated values (age, BMI, BMR) are never stored —
    // see PersonalProfileCalculations — they're derived fresh from these
    // raw fields wherever they're needed.

    var dateOfBirth: Date?
    /// male | female | unspecified — asked only for BMR/calorie-estimate
    /// formulas, which differ by biological sex; "unspecified" skips those
    /// calculations rather than guessing.
    var biologicalSex: String?
    var heightCm: Double?
    var currentWeightKg: Double?
    var targetWeightKg: Double?

    // Body composition
    var bodyFatPercent: Double?
    var waistCm: Double?
    var hipCm: Double?

    // Training background
    /// under_1 | one_to_three | three_to_five | five_plus
    var yearsTrainingBucket: String?
    /// Free text — past programs/styles, what's worked or hasn't. Kept out
    /// of the compact per-call context snapshot (see ContextBuilder) since
    /// it can run long; read by Kai only where a call site explicitly pulls
    /// it in.
    var trainingBackgroundNotes: String?
    /// Free text — what's actually driving them right now. Same context-
    /// snapshot exclusion as trainingBackgroundNotes above.
    var motivationNotes: String?

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
        case trainingSplit         = "training_split"
        case exerciseVariability   = "exercise_variability"
        case warmupSetsEnabled     = "warmup_sets_enabled"
        case circuitsSupersetsEnabled = "circuits_supersets_enabled"
        case weightUnit            = "weight_unit"
        case startOfWeek           = "start_of_week"
        case dateOfBirth           = "date_of_birth"
        case biologicalSex         = "biological_sex"
        case heightCm              = "height_cm"
        case currentWeightKg       = "current_weight_kg"
        case targetWeightKg        = "target_weight_kg"
        case bodyFatPercent        = "body_fat_percent"
        case waistCm               = "waist_cm"
        case hipCm                 = "hip_cm"
        case yearsTrainingBucket   = "years_training_bucket"
        case trainingBackgroundNotes = "training_background_notes"
        case motivationNotes       = "motivation_notes"
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
            trainingSplit: "let_kai_decide",
            exerciseVariability: "moderate",
            warmupSetsEnabled: true,
            circuitsSupersetsEnabled: false,
            weightUnit: "lbs",
            startOfWeek: "monday",
            dateOfBirth: nil,
            biologicalSex: nil,
            heightCm: nil,
            currentWeightKg: nil,
            targetWeightKg: nil,
            bodyFatPercent: nil,
            waistCm: nil,
            hipCm: nil,
            yearsTrainingBucket: nil,
            trainingBackgroundNotes: nil,
            motivationNotes: nil,
            onboardingComplete: false,
            subscriptionTier: .free,
            subscriptionExpiresAt: nil,
            createdAt: .now,
            updatedAt: .now
        )
    }
}
