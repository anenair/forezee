// ============================================================
// SubscriptionTier.swift
// Forzee — Core/Models
//
// Represents the user's subscription state.
// Sourced from RevenueCat and cached in `profiles.subscription_tier`.
// ============================================================

import Foundation

enum SubscriptionTier: String, Codable, Equatable {
    case free    = "free"
    case premium = "premium"

    var isFree: Bool    { self == .free }
    var isPremium: Bool { self == .premium }

    /// Human-readable display name.
    var displayName: String {
        switch self {
        case .free:    return "Free"
        case .premium: return "Premium"
        }
    }
}
