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
//     "recent_context": { sleep, hrv, steps, stress, weather, calendar, nutrition, workouts },
//     "conversation_summary": "Rolling summary — NOT full chat history"
//   }
//
// Phase 1: user profile only (no HealthKit/calendar signals yet)
// Phase 2: real sleep, HRV, steps, mindfulness, calendar, and weather
//          signals — every source degrades to nil if unauthorized or
//          unavailable so Kai never blocks on a missing signal.
// ============================================================

import Foundation

final class ContextBuilder {

    // MARK: - Public

    /// Build a full context snapshot for the given user.
    /// Pulls from Supabase profile + workout history, plus the Phase 2
    /// life-signal pipeline (HealthKit, EventKit, WeatherKit).
    func buildSnapshot(userId: String) async -> UserContextSnapshot {
        async let profile = fetchProfile(userId: userId)
        async let workoutSummary = fetchWorkoutSummary(userId: userId)
        async let conversationSummary = fetchConversationSummary(userId: userId)
        async let lifeSignals = fetchLifeSignals(userId: userId)

        let (p, ws, cs, ls) = await (profile, workoutSummary, conversationSummary, lifeSignals)

        return UserContextSnapshot(
            user: buildUserContext(from: p),
            recentContext: buildRecentContext(workoutSummary: ws, lifeSignals: ls),
            conversationSummary: cs
        )
    }

    // MARK: - Private — Profile & History

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

    // MARK: - Private — Life Signals (Phase 2)

    private func fetchLifeSignals(userId: String) async -> LifeSignals {
        async let sleepAvg = HealthKitManager.shared.fetchSleepAvg7d()
        async let hrvTrend = HealthKitManager.shared.fetchHRVTrend()
        async let stepsToday = HealthKitManager.shared.fetchStepsToday()
        async let mindfulMinutes = HealthKitManager.shared.fetchMindfulMinutesToday()
        async let calendarToday = CalendarManager.shared.todayBusyness()
        async let weather = WeatherManager.shared.fetchTodaySignal()
        async let nutritionToday = fetchNutritionSummary(userId: userId)

        let signals = await LifeSignals(
            sleepAvg7d: sleepAvg,
            hrvTrend: hrvTrend,
            stepsToday: stepsToday,
            mindfulMinutesToday: mindfulMinutes,
            calendarToday: calendarToday,
            weather: weather,
            nutritionToday: nutritionToday
        )

        await persistSignals(signals, userId: userId)
        return signals
    }

    private func fetchNutritionSummary(userId: String) async -> NutritionSummary {
        (try? await ForzeeDataService.shared.fetchNutritionToday(userId: userId)) ?? .empty
    }

    /// Best-effort write-through to `context_signals` for trend history
    /// (e.g. "HRV declining" is computed from this over time). Never blocks
    /// or fails the context snapshot if a write drops.
    private func persistSignals(_ signals: LifeSignals, userId: String) async {
        var records: [ContextSignal] = []

        if let sleep = signals.sleepAvg7d {
            records.append(ContextSignal(userId: userId, signalType: .sleep, valueNumeric: sleep, valueText: nil))
        }
        if let hrv = signals.hrvTrend {
            records.append(ContextSignal(userId: userId, signalType: .hrv, valueNumeric: nil, valueText: hrv))
        }
        if let steps = signals.stepsToday {
            records.append(ContextSignal(userId: userId, signalType: .steps, valueNumeric: Double(steps), valueText: nil))
        }
        if let mindful = signals.mindfulMinutesToday {
            records.append(ContextSignal(userId: userId, signalType: .stress, valueNumeric: Double(mindful), valueText: nil))
        }
        if let calendar = signals.calendarToday {
            records.append(ContextSignal(userId: userId, signalType: .calendarBusyness, valueNumeric: nil, valueText: calendar))
        }
        if let weather = signals.weather {
            records.append(ContextSignal(userId: userId, signalType: .weather, valueNumeric: nil, valueText: weather.condition))
        }

        for record in records {
            try? await ForzeeDataService.shared.insertContextSignal(record)
        }
    }

    // MARK: - Private — Snapshot Assembly

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
        workoutSummary: WorkoutHistorySummary,
        lifeSignals: LifeSignals
    ) -> UserContextSnapshot.RecentContext {
        return UserContextSnapshot.RecentContext(
            sleepAvg7d: lifeSignals.sleepAvg7d,
            hrvTrend: lifeSignals.hrvTrend,
            workoutsThisWeek: workoutSummary.workoutsThisWeek,
            lastSession: workoutSummary.lastSessionDescription,
            calendarToday: lifeSignals.calendarToday,
            stepsToday: lifeSignals.stepsToday,
            stressMinutesToday: lifeSignals.mindfulMinutesToday,
            weatherCondition: lifeSignals.weather?.condition,
            outdoorFriendly: lifeSignals.weather?.outdoorFriendly,
            nutritionToday: lifeSignals.nutritionToday.entryCount > 0
                ? "\(lifeSignals.nutritionToday.totalCalories) cal, \(lifeSignals.nutritionToday.totalProteinG)g protein logged"
                : nil
        )
    }
}

// MARK: - LifeSignals

/// Raw Phase 2 signal bundle, before compression into the snapshot.
private struct LifeSignals {
    let sleepAvg7d: Double?
    let hrvTrend: String?
    let stepsToday: Int?
    let mindfulMinutesToday: Int?
    let calendarToday: String?
    let weather: WeatherManager.Signal?
    let nutritionToday: NutritionSummary
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
        let sleepAvg7d: Double?          // Phase 2 — hours, HealthKit
        let hrvTrend: String?            // Phase 2 — "declining" | "stable" | "improving", HealthKit
        let workoutsThisWeek: Int
        let lastSession: String?         // e.g. "Push — 3 days ago"
        let calendarToday: String?       // Phase 2 — "busy_afternoon" | "free" | "travel", EventKit
        let stepsToday: Int?             // Phase 2 — HealthKit
        let stressMinutesToday: Int?     // Phase 2 — mindful minutes, HealthKit proxy
        let weatherCondition: String?    // Phase 2 — WeatherKit, e.g. "Clear, 68°F"
        let outdoorFriendly: Bool?       // Phase 2 — WeatherKit
        let nutritionToday: String?      // Phase 2 — manual macro log summary
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
