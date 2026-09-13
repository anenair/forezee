// ============================================================
// SessionFeedback.swift
// Forzee — Core/Models
//
// The user's own account of a finished workout — effort, mood,
// rating, notes. Collected once, at the final "Save Session" step,
// and saved together with the session record in a single local
// write (see ForzeeDataService.saveCompletedWorkout). Fields map
// directly to the `sessions` table columns already defined in
// forzee_schema.sql — they just had no UI collecting them until now.
// ============================================================

import Foundation

struct SessionFeedback {
    /// 1-10, RPE-style (Rate of Perceived Exertion). Optional — a user
    /// can save a session without rating effort.
    var perceivedEffort: Int?
    var mood: Mood?
    var notes: String?
    /// 1-5 overall session rating.
    var rating: Int?

    static let empty = SessionFeedback(perceivedEffort: nil, mood: nil, notes: nil, rating: nil)

    enum Mood: String, CaseIterable, Identifiable {
        case great, good, okay, tired, rough

        var id: String { rawValue }

        var label: String { rawValue.capitalized }

        var iconSystemName: String {
            switch self {
            case .great: return "sun.max.fill"
            case .good:  return "sun.min.fill"
            case .okay:  return "cloud.fill"
            case .tired: return "cloud.drizzle.fill"
            case .rough: return "cloud.bolt.fill"
            }
        }
    }
}
