// ============================================================
// UsageRecord.swift
// Forzee — Core/Models
//
// Maps to the `usage_tracking` table in Supabase.
// Used by UsageGate to record API calls and enforce free limits.
// ============================================================

import Foundation

struct UsageRecord: Codable {
    let userId: String
    let taskType: String
    let modelUsed: String
    let inputTokens: Int
    let outputTokens: Int
    let estimatedCostUsd: Double

    enum CodingKeys: String, CodingKey {
        case userId           = "user_id"
        case taskType         = "task_type"
        case modelUsed        = "model_used"
        case inputTokens      = "input_tokens"
        case outputTokens     = "output_tokens"
        case estimatedCostUsd = "estimated_cost_usd"
    }
}
