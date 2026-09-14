// ============================================================
// InsightsEngine.swift
// Forzee — Core/AI
//
// Pure aggregation over already-fetched session history — no I/O,
// no Supabase calls of its own. Powers roadmap Phase 3 "Insights":
// Weekly Set Targets, Recovery, and the volume/recovery/Momentum
// summary that feeds Kai's weekly read skill.
// ============================================================

import Foundation

enum InsightsEngine {

    // MARK: - Weekly Set Volume

    /// Sets per muscle group in the trailing `trailingDays` (default 7) —
    /// counts each logged set once, against its exercise's *primary*
    /// muscle group only. Secondary groups aren't double-counted; that's a
    /// deliberate simplification for a first version, not an oversight.
    static func weeklySetVolume(
        sessions: [SessionHistoryEntry],
        trailingDays: Int = 7,
        asOf now: Date = .now
    ) -> [MuscleGroup: Int] {
        let cutoff = now.addingTimeInterval(-Double(trailingDays) * 86400)
        var counts: [MuscleGroup: Int] = [:]

        for session in sessions where session.startedAt >= cutoff {
            let lookup = muscleGroupByExerciseName(session)
            for set in session.setsLog {
                guard let name = set.exerciseName, let group = lookup[name] else { continue }
                counts[group, default: 0] += 1
            }
        }
        return counts
    }

    // MARK: - Recovery

    /// Days since each muscle group was last trained, across the sessions
    /// handed in — callers pass a wide-enough lookback (see
    /// ForzeeDataService.fetchSessionHistory's limit) for this to be
    /// meaningful. A group absent from the returned dict wasn't trained
    /// anywhere in the window passed in, not "just now" — callers should
    /// read a missing key as "no recent data," not "fully recovered."
    static func daysSinceLastTrained(
        sessions: [SessionHistoryEntry],
        asOf now: Date = .now
    ) -> [MuscleGroup: Int] {
        var lastTrained: [MuscleGroup: Date] = [:]

        for session in sessions {
            let lookup = muscleGroupByExerciseName(session)
            let groupsThisSession = Set(session.setsLog.compactMap { $0.exerciseName.flatMap { lookup[$0] } })
            for group in groupsThisSession where lastTrained[group] == nil || session.startedAt > lastTrained[group]! {
                lastTrained[group] = session.startedAt
            }
        }

        return lastTrained.mapValues { date in
            max(0, Int(now.timeIntervalSince(date) / 86400))
        }
    }

    // MARK: - Momentum

    /// A decay-weighted consistency score, 0-100 — computed fresh each time
    /// from session dates, not a stored value. Sessions count for less the
    /// further back they are (14-day falloff) rather than resetting to zero
    /// the moment a day is missed — Kai's "Momentum, not streaks" philosophy
    /// (see KaiSystemPrompt.coachingPhilosophy) expressed as an actual
    /// number instead of only ever being a line in a system prompt.
    static func momentumScore(sessions: [SessionHistoryEntry], asOf now: Date = .now) -> Int {
        let points = sessions.reduce(0.0) { total, session in
            let daysAgo = now.timeIntervalSince(session.startedAt) / 86400
            guard daysAgo >= 0, daysAgo <= 28 else { return total }
            let weight = max(0, 1 - daysAgo / 14)
            return total + weight
        }
        // 4 full-weight sessions in the last 14 days ≈ 100.
        return min(100, Int((points / 4.0) * 100))
    }

    // MARK: - Private

    /// A session's sets_log only carries exercise_name (see LoggedSetRecord
    /// in ForzeeDataService) — the muscle-group tag lives on the
    /// *originating workout's* exercise list instead, so every lookup here
    /// cross-references the two by name.
    private static func muscleGroupByExerciseName(_ session: SessionHistoryEntry) -> [String: MuscleGroup] {
        guard let exercises = session.workout?.exercises else { return [:] }
        var lookup: [String: MuscleGroup] = [:]
        for exercise in exercises {
            guard let group = exercise.primaryMuscleGroup else { continue }
            lookup[exercise.name] = group
        }
        return lookup
    }
}
