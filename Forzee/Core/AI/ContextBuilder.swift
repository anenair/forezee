// ============================================================
// ContextBuilder.swift
// Forzee — Core/AI
//
// Assembles the compressed user context snapshot that feeds
// every Claude API call. This snapshot is Kai's window into
// the user's life.
//
// Token budget: the entire snapshot must remain compact.
// Target: context snapshot < 500 tokens, system + full input < 2,000.
//
// Snapshot structure:
//   {
//     "user": { level, goals, equipment, limitations },
//     "recent_context": { sleep, hrv, workouts_this_week, last_session, calendar },
//     "conversation_summary": "Rolling summary — NOT full chat history"
//   }
//
// Phase 1: user profile only (no HealthKit/calendar signals yet)
// Phase 2: add real sleep, HRV, calendar, stress signals
// ============================================================

import Foundation

final class ContextBuilder {

    // MARK: - Public

    /// Build a full context snapshot for the given user.
    /// Phase 1: pulls from Supabase profile + workout history.
    /// Phase 2: will additionally pull from HealthKit, EventKit, etc.
    func buildSnapshot(userId: String) async -> UserContextSnapshot {
        async let profile = fetchProfile(userId: userId)
        async let workoutSummary = fetchWorkoutSummary(userId: userId)
        async let conversationSummary = fetchConversationSummary(userId: userId)

        let (p, ws, cs) = await (profile, workoutSummary, conversationSummary)

        return UserContextSnapshot(
            user: buildUserContext(from: p),
            recentContext: buildRecentContext(workoutSummary: ws),
            conversationSummary: cs
        )
    }

    // MARK: - Private

    private func fetchProfile(userId: String) async -> UserProfile? {
        try? await ForzeeDataService.shared.fetchProfile(userId: userId)
    }

    private func fetchWorkoutSummary(userId: String) async -> WorkoutHistorySummary {
        // TODO: Implement — query recent sessions from Supabase
        return WorkoutHistorySummary.empty
    }

    private func fetchConversationSummary(userId: String) async -> String {
        // TODO: Implement — fetch rolling summary from coach_messages
        // Never send full chat history — only the compressed rolling summary
        return ""
    }

    private func buildUserContext(from profile: UserProfile?) -> UserContextSnapshot.UserContext {
        guard let profile else {
            return UserContextSnapshot.UserContext(
                level: "novice",
                goals: [],
                equipment: ["bodyweight"],
                limitations: nil
            )
        }
        return UserContextSnapshot.UserContext(
            level: profile.fitnessLevel,
            goals: profile.goals,
            equipment: profile.equipment,
            limitations: profile.limitations
        )
    }

    private func buildRecentContext(
        workoutSummary: WorkoutHistorySummary
    ) -> UserContextSnapshot.RecentContext {
        // Phase 1: workout history only. Phase 2 adds sleep/HRV/calendar.
        return UserContextSnapshot.RecentContext(
            sleepAvg7d: nil,           // Phase 2: HealthKit
            hrvTrend: nil,             // Phase 2: HealthKit
            workoutsThisWeek: workoutSummary.workoutsThisWeek,
            lastSession: workoutSummary.lastSessionDescription,
            calendarToday: nil         // Phase 2: EventKit
        )
    }
}

// MARK: - UserContextSnapshot

/// The compressed snapshot passed to Claude on every call.
/// Must stay lean — target < 500 tokens as JSON.
struct UserContextSnapshot: Codable {

    struct UserContext: Codable {
        let level: String          // novice | returning | intermediate | advanced
        let goals: [String]        // e.g. ["build_muscle", "lose_weight"]
        let equipment: [String]    // e.g. ["full_gym"]
        let limitations: String?   // free text — e.g. "left knee discomfort"
    }

    struct RecentContext: Codable {
        let sleepAvg7d: Double?    // Phase 2 — hours
        let hrvTrend: String?      // Phase 2 — "declining" | "stable" | "improving"
        let workoutsThisWeek: Int
        let lastSession: String?   // e.g. "Push — 3 days ago"
        let calendarToday: String? // Phase 2 — "busy_afternoon" | "free" | "travel"
    }

    let user: UserContext
    let recentContext: RecentContext
    let conversationSummary: String

    /// Encode to compact JSON string for inclusion in system prompt.
    func toCompactJSON() -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = []
        guard let data = try? encoder.encode(self),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

// MARK: - WorkoutHistorySummary

struct WorkoutHistorySummary {
    let workoutsThisWeek: Int
    let lastSessionDescription: String?

    static let empty = WorkoutHistorySummary(workoutsThisWeek: 0, lastSessionDescription: nil)
}
