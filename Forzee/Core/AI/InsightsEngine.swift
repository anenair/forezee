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

            var groupsThisSession: Set<MuscleGroup> = []
            for set in session.setsLog {
                guard let name = set.exerciseName, let group = lookup[name] else { continue }
                groupsThisSession.insert(group)
            }

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

    // MARK: - Period Reports (Monthly / Annual)

    /// Summary stats for everything in `since...until` — powers the
    /// Progress tab's Month/Year report toggle, including browsing to a
    /// past month/year (see ReportsSection's navigation), not just the
    /// current one. Callers pass a wide-enough session fetch (see
    /// ForzeeDataService.fetchSessionHistory's since: parameter) for the
    /// range to actually be meaningful; this itself does the date
    /// filtering, so the same fetched array works for any period viewed.
    struct PeriodReport {
        let totalSessions: Int
        let totalVolumeKg: Double
        let mostTrainedMuscleGroup: MuscleGroup?
        let mostRepeatedWorkoutId: String?
        let mostRepeatedWorkoutName: String?
        let mostRepeatedWorkoutCount: Int
        let momentumScore: Int
    }

    static func periodReport(
        sessions: [SessionHistoryEntry],
        since: Date,
        until: Date = .now
    ) -> PeriodReport {
        let inRange = sessions.filter { $0.startedAt >= since && $0.startedAt <= until }

        var groupCounts: [MuscleGroup: Int] = [:]
        var workoutCounts: [String: Int] = [:]
        var workoutNames: [String: String] = [:]

        for session in inRange {
            let lookup = muscleGroupByExerciseName(session)
            for set in session.setsLog {
                guard let name = set.exerciseName, let group = lookup[name] else { continue }
                groupCounts[group, default: 0] += 1
            }
            if let workoutId = session.workoutId {
                workoutCounts[workoutId, default: 0] += 1
                if let name = session.workout?.name {
                    workoutNames[workoutId] = name
                }
            }
        }

        let topGroup = groupCounts.max { $0.value < $1.value }?.key
        let topWorkout = workoutCounts.max { $0.value < $1.value }

        return PeriodReport(
            totalSessions: inRange.count,
            totalVolumeKg: inRange.reduce(0) { $0 + $1.totalVolumeKg },
            mostTrainedMuscleGroup: topGroup,
            mostRepeatedWorkoutId: topWorkout?.key,
            mostRepeatedWorkoutName: topWorkout.flatMap { workoutNames[$0.key] },
            mostRepeatedWorkoutCount: topWorkout?.value ?? 0,
            // "As of" the end of the window being viewed, not real "now" —
            // for a past month/year, momentum should read as it stood at
            // the time, not decayed further by everything since.
            momentumScore: momentumScore(sessions: inRange, asOf: until)
        )
    }

    static func startOfMonth(_ date: Date = .now) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.start ?? date
    }

    static func endOfMonth(_ date: Date = .now) -> Date {
        Calendar.current.dateInterval(of: .month, for: date)?.end ?? date
    }

    static func startOfYear(_ date: Date = .now) -> Date {
        Calendar.current.dateInterval(of: .year, for: date)?.start ?? date
    }

    static func endOfYear(_ date: Date = .now) -> Date {
        Calendar.current.dateInterval(of: .year, for: date)?.end ?? date
    }

    // MARK: - Personal Bests

    /// Heaviest weight×reps ever logged for an exercise name, kept as a
    /// frozen snapshot rather than something that recomputes live — see
    /// WorkoutTabView's PR-detection banner, which loads this once when a
    /// workout starts specifically so a set only ever competes against
    /// what was already true walking in.
    struct PersonalBest {
        let weightKg: Double
        let reps: Int
    }

    static func personalBests(sessions: [SessionHistoryEntry]) -> [String: PersonalBest] {
        var bests: [String: PersonalBest] = [:]
        for session in sessions {
            for set in session.setsLog {
                guard let name = set.exerciseName, let weightKg = set.weightKg, let reps = set.reps,
                      weightKg > 0, reps > 0 else { continue }
                let current = bests[name]
                if current == nil || weightKg > current!.weightKg || (weightKg == current!.weightKg && reps > current!.reps) {
                    bests[name] = PersonalBest(weightKg: weightKg, reps: reps)
                }
            }
        }
        return bests
    }

    // MARK: - Exercise Progress

    /// The top logged weight for `exerciseName` in its most recent session
    /// vs. the session before that (only among sessions that actually
    /// touched this exercise — sessions where it wasn't done don't count
    /// as "no progress," they're just not in this comparison at all).
    /// `previous` is nil the first time an exercise has ever been logged —
    /// there's nothing to compare against yet, not a zero.
    ///
    /// Powers Kai's `show_progress` skill (see KaiEngine.sendCoachMessage)
    /// — the numbers here are real, computed from actual logged sets, and
    /// are what the app hands Kai to report rather than anything the model
    /// could invent on its own (matches the system prompt's "never
    /// fabricate health data" rule).
    struct ExerciseProgress {
        let current: Double
        let previous: Double?
    }

    static func exerciseProgress(sessions: [SessionHistoryEntry], exerciseName: String) -> ExerciseProgress? {
        let matching = sessions
            .compactMap { session -> (date: Date, topWeightKg: Double)? in
                let topWeight = session.setsLog
                    .filter { $0.exerciseName?.caseInsensitiveCompare(exerciseName) == .orderedSame }
                    .compactMap(\.weightKg)
                    .max()
                guard let topWeight, topWeight > 0 else { return nil }
                return (session.startedAt, topWeight)
            }
            .sorted { $0.date > $1.date } // newest first

        guard let latest = matching.first else { return nil }
        let previous = matching.dropFirst().first?.topWeightKg
        return ExerciseProgress(current: latest.topWeightKg, previous: previous)
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
