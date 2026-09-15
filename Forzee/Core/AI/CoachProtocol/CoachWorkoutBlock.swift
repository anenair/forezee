// ============================================================
// CoachWorkoutBlock.swift
// Forzee — Core/AI/CoachProtocol
//
// The workout-shaped payload of a WorkoutBlock — Kai's PROPOSAL,
// never the app's canonical workout. WorkoutBuilder.build(from:)
// is the one place a CoachWorkout becomes a real GeneratedWorkout
// (the app's existing, authoritative model); see that file.
// ============================================================

import Foundation

struct WorkoutBlock: Codable, Equatable {
    var type: String = "workout"
    var workout: CoachWorkout
}

struct CoachWorkout: Codable, Equatable {
    /// Present only if the model happens to echo one back (e.g. modifying
    /// a workout it proposed earlier in the same conversation) — never
    /// trusted as a real id. WorkoutBuilder always mints its own.
    var id: String?
    var title: String
    var estimatedDurationMinutes: Int?
    var exercises: [CoachExercise]
}

struct CoachExercise: Codable, Equatable {
    /// Never trusted as-is — WorkoutBuilder re-resolves by `name` against
    /// ExerciseCatalog rather than taking an LLM-supplied id at face value.
    var exerciseId: String?
    var name: String
    var prescription: ExercisePrescription
    var notes: String?
}
