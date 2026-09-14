// ============================================================
// UsageGate.swift
// Forzee — Core/AI
//
// Enforces free-tier API usage limits and records usage for
// cost monitoring.
//
// Free tier limits (per day):
//   - chat_message:       3
//   - workout_generation: 1 (per week)
//   - daily_briefing:     1 (always free — no cap)
//
// Premium tier: unlimited (gate always passes)
//
// Limits are enforced by querying Supabase `usage_tracking`
// and checking against `daily_usage_summary` view.
// ============================================================

import Foundation

final class UsageGate {

    // MARK: - Limits

    private let freeTierDailyLimits: [KaiTaskType: Int] = [
        .chatMessage:       3,
        .workoutGeneration: 1,  // Note: weekly reset — enforced separately
        .dailyBriefing:     .max  // Always free, no limit
    ]

    // MARK: - Check

    /// Check whether the user is allowed to make this API call.
    /// Throws `UsageGateError.limitReached` if the free-tier limit is hit.
    func checkLimit(userId: String, taskType: KaiTaskType) async throws {
        // Premium users pass through unconditionally
        let tier = await fetchSubscriptionTier(userId: userId)
        guard tier == .free else { return }

        // Daily briefing is always free
        guard taskType != .dailyBriefing else { return }

        let todayUsage = await fetchTodayUsage(userId: userId, taskType: taskType)
        let limit = freeTierDailyLimits[taskType] ?? .max

        if todayUsage >= limit {
            throw UsageGateError.limitReached(
                taskType: taskType,
                limit: limit,
                used: todayUsage
            )
        }
    }

    // MARK: - Record

    /// Record a completed API call for cost monitoring and limit enforcement.
    func recordUsage(
        userId: String,
        taskType: KaiTaskType,
        model: KaiModel,
        inputTokens: Int,
        outputTokens: Int
    ) async {
        await recordUsage(
            userId: userId,
            taskType: taskType.rawValue,
            model: model,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    /// Same as above, keyed by a raw task-type string instead of a
    /// `KaiTaskType` case — what the generic skill runner uses, since a
    /// bundled skill's own name is what usage tracks under, not a case in
    /// this closed enum. A new skill needs nothing added here to be tracked.
    func recordUsage(
        userId: String,
        taskType: String,
        model: KaiModel,
        inputTokens: Int,
        outputTokens: Int
    ) async {
        // Cost estimates (USD per million tokens, as of 2025)
        let inputCostPerMillion: Double = model == .haiku ? 0.25 : 3.00
        let outputCostPerMillion: Double = model == .haiku ? 1.25 : 15.00

        let estimatedCost = (Double(inputTokens) / 1_000_000 * inputCostPerMillion)
                          + (Double(outputTokens) / 1_000_000 * outputCostPerMillion)

        let record = UsageRecord(
            userId: userId,
            taskType: taskType,
            modelUsed: model.rawValue,
            inputTokens: inputTokens,
            outputTokens: outputTokens,
            estimatedCostUsd: estimatedCost
        )

        do {
            try await ForzeeDataService.shared.insertUsageRecord(record)
        } catch {
            // Non-fatal — log and continue. Never block the user on usage recording.
            #if DEBUG
            print("UsageGate: failed to record usage — \(error.localizedDescription)")
            #endif
        }
    }

    // MARK: - Private

    private func fetchSubscriptionTier(userId: String) async -> SubscriptionTier {
        guard let profile = try? await ForzeeDataService.shared.fetchProfile(userId: userId) else {
            return .free
        }
        return profile.subscriptionTier
    }

    private func fetchTodayUsage(userId: String, taskType: KaiTaskType) async -> Int {
        // TODO: Query daily_usage_summary view from Supabase
        // For now returns 0 — implement before any free-tier user testing
        return 0
    }
}

// MARK: - UsageGateError

enum UsageGateError: LocalizedError {
    case limitReached(taskType: KaiTaskType, limit: Int, used: Int)

    var errorDescription: String? {
        switch self {
        case .limitReached(let taskType, let limit, _):
            switch taskType {
            case .chatMessage:
                return "You've reached your \(limit) free messages for today. Upgrade to Premium for unlimited coaching."
            case .workoutGeneration:
                return "You've used your free AI workout for this week. Upgrade to Premium for daily adaptive workouts."
            default:
                return "You've reached your free limit for this feature. Upgrade to Premium for unlimited access."
            }
        }
    }
}
