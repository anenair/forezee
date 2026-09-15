// ============================================================
// MuscleGroup.swift
// Forzee — Core/Models
//
// The canonical muscle-group vocabulary Kai tags exercises with at
// generation time (see WorkoutGenerationPrompt, or CoachProtocol's
// ExerciseCatalog for the Coach chat path) — the plumbing roadmap
// Phase 3 "Insights" is built on top of: Weekly Set Targets, Recovery,
// and Kai's weekly read all read this same tag rather than each
// inventing their own grouping.
// ============================================================

import Foundation

enum MuscleGroup: String, Codable, CaseIterable {
    case chest
    case back
    case shoulders
    case biceps
    case triceps
    case quads
    case hamstrings
    case glutes
    case calves
    case core
    case fullBody = "full_body"

    var displayName: String {
        switch self {
        case .chest:      return "Chest"
        case .back:       return "Back"
        case .shoulders:  return "Shoulders"
        case .biceps:     return "Biceps"
        case .triceps:    return "Triceps"
        case .quads:      return "Quads"
        case .hamstrings: return "Hamstrings"
        case .glutes:     return "Glutes"
        case .calves:     return "Calves"
        case .core:       return "Core"
        case .fullBody:   return "Full Body"
        }
    }

    /// A reasonable trailing-7-day working-set target per group — evidence-based
    /// ranges (roughly 10-20 sets/week for major groups) collapsed to one
    /// number each. Not user-customizable yet; that's real future scope
    /// (the "My Plan" settings screen, roadmap Phase 4), not something to
    /// half-build here.
    var weeklySetTarget: Int {
        switch self {
        case .chest:      return 12
        case .back:       return 14
        case .shoulders:  return 12
        case .biceps:     return 8
        case .triceps:    return 8
        case .quads:      return 12
        case .hamstrings: return 10
        case .glutes:     return 10
        case .calves:     return 8
        case .core:       return 8
        case .fullBody:   return 6
        }
    }
}
