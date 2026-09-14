// ============================================================
// LoggedSet.swift
// Forzee — Core/Models
//
// A single completed set with actual weight/reps — what the user
// really did, not just the prescription. Didn't exist before this;
// WorkoutTabView only tracked whole-exercise completion. Voice
// logging ("135 lbs, 8 reps") needs this level of detail to mean
// anything.
// ============================================================

import Foundation

struct LoggedSet: Identifiable, Equatable {
    let id: UUID
    let exerciseId: UUID
    let setNumber: Int
    var weightValue: Double?
    var weightUnit: WeightUnit?
    var reps: Int?
    var restSecs: Int?
    let loggedAt: Date

    init(
        exerciseId: UUID,
        setNumber: Int,
        weightValue: Double? = nil,
        weightUnit: WeightUnit? = nil,
        reps: Int? = nil,
        restSecs: Int? = nil
    ) {
        self.id = UUID()
        self.exerciseId = exerciseId
        self.setNumber = setNumber
        self.weightValue = weightValue
        self.weightUnit = weightUnit
        self.reps = reps
        self.restSecs = restSecs
        self.loggedAt = .now
    }
}

enum WeightUnit: String {
    case lbs
    case kg

    var spokenName: String {
        switch self {
        case .lbs: return "pounds"
        case .kg:  return "kilograms"
        }
    }
}
