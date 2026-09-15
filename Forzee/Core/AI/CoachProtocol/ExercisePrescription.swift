// ============================================================
// ExercisePrescription.swift
// Forzee — Core/AI/CoachProtocol
//
// How much of an exercise to do — a discriminated union rather
// than one fixed sets×reps shape, because not everything is
// sets×reps: a plank is a duration, a rep-range set has no single
// target rep count. Three cases are implemented for v1 (reps,
// duration, repRange); `.unknown` is the forward-compat case, so a
// future prescription type (percentageOf1RM, EMOM, tempo, drop
// sets, AMRAP) decodes without crashing the chat — it just can't
// be executed until a real case is added for it.
//
// Every case exposes a legacy sets/reps-text/rest view (see the
// `legacy*` properties) so WorkoutBuilder can populate the
// existing WorkoutExercise's flat sets/reps/restSecs fields — the
// ones WorkoutTabView's per-set editor is already built around —
// without that editor needing to know prescriptions exist yet.
// ============================================================

import Foundation

enum ExercisePrescription: Codable, Equatable {
    case reps(RepsPrescription)
    case duration(DurationPrescription)
    case repRange(RepRangePrescription)
    /// Decode-only fallback for a prescription type this build doesn't
    /// understand yet — never a decode failure, just inert until a real
    /// case exists for it.
    case unknown(type: String)

    // MARK: - Reps

    struct RepsPrescription: Codable, Equatable {
        var sets: Int
        var reps: Int
        var restSeconds: Int?
        /// Reps in reserve — how many more the set could have taken.
        /// Optional; nothing reads this yet, reserved for when a profile
        /// tracks RPE/RIR.
        var rir: Int?
    }

    // MARK: - Duration

    struct DurationPrescription: Codable, Equatable {
        var sets: Int
        var durationSeconds: Int
        var restSeconds: Int?
    }

    // MARK: - Rep Range

    struct RepRangePrescription: Codable, Equatable {
        var sets: Int
        var repsMin: Int
        var repsMax: Int
        var restSeconds: Int?
        var rir: Int?
    }

    // MARK: - Codable
    //
    // Same flat discriminator pattern as CoachBlock: "type" decides which
    // payload struct to decode the REST of the same object into, and
    // encode writes "type" plus that payload's own fields back onto one
    // shared container rather than nesting a sub-object.

    private enum TypeKey: String, CodingKey { case type }

    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)
        switch type {
        case "reps":      self = .reps(try RepsPrescription(from: decoder))
        case "duration":  self = .duration(try DurationPrescription(from: decoder))
        case "rep_range": self = .repRange(try RepRangePrescription(from: decoder))
        default:          self = .unknown(type: type)
        }
    }

    func encode(to encoder: Encoder) throws {
        var typeContainer = encoder.container(keyedBy: TypeKey.self)
        switch self {
        case .reps(let p):
            try typeContainer.encode("reps", forKey: .type)
            try p.encode(to: encoder)
        case .duration(let p):
            try typeContainer.encode("duration", forKey: .type)
            try p.encode(to: encoder)
        case .repRange(let p):
            try typeContainer.encode("rep_range", forKey: .type)
            try p.encode(to: encoder)
        case .unknown(let type):
            try typeContainer.encode(type, forKey: .type)
        }
    }

    // MARK: - Legacy Bridge

    var legacySets: Int {
        switch self {
        case .reps(let p):     return p.sets
        case .duration(let p): return p.sets
        case .repRange(let p): return p.sets
        case .unknown:         return 1
        }
    }

    var legacyRepsText: String {
        switch self {
        case .reps(let p):     return "\(p.reps)"
        case .duration(let p): return "\(p.durationSeconds) sec"
        case .repRange(let p): return "\(p.repsMin)-\(p.repsMax)"
        case .unknown:         return "-"
        }
    }

    var legacyRestSeconds: Int {
        switch self {
        case .reps(let p):     return p.restSeconds ?? 90
        case .duration(let p): return p.restSeconds ?? 90
        case .repRange(let p): return p.restSeconds ?? 90
        case .unknown:         return 90
        }
    }
}
