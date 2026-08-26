// ============================================================
// ContextSignal.swift
// Forzee — Core/Models
//
// Maps to the `context_signals` table in Supabase.
// Every Phase 2 life signal ContextBuilder reads gets written
// here too, so trends (e.g. HRV over time) can be computed
// from history rather than just the last snapshot.
// ============================================================

import Foundation

struct ContextSignal: Codable {

    var userId: String
    var signalType: SignalType
    var valueNumeric: Double?
    var valueText: String?

    enum SignalType: String, Codable {
        case sleep
        case hrv
        case steps
        case stress
        case calendarBusyness = "calendar_busyness"
        case weather
    }

    enum CodingKeys: String, CodingKey {
        case userId       = "user_id"
        case signalType   = "signal_type"
        case valueNumeric = "value_numeric"
        case valueText    = "value_text"
    }
}
