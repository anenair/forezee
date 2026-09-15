// ============================================================
// WorkoutSessionManager.swift
// Forzee — Core/Workout
//
// The single owner of "what workout is in progress right now" —
// the workout itself, which exercises are done, and every set
// logged so far. Three surfaces need to read and mutate this same
// state: WorkoutTabView's manual per-set entry, WorkoutTabView's
// own voice mode, and Coach chat's log_set action. Before this,
// that state lived only in WorkoutTabView's private @State, so
// none of it was visible outside that one view, and the same
// "resolve a set against whatever's current" logic was duplicated
// between manual entry and voice.
//
// Nothing here is persisted until `finish` is called — that's
// still the one atomic sync-to-backend moment (via
// ForzeeDataService.saveCompletedWorkout), unchanged from before.
// A session in progress lives only in memory, same as today.
// ============================================================

import Foundation

@MainActor
final class WorkoutSessionManager: ObservableObject {

    static let shared = WorkoutSessionManager()
    private init() {}

    // MARK: - Published State

    @Published private(set) var workout: GeneratedWorkout?
    @Published private(set) var completedExerciseIds: Set<UUID> = []
    @Published private(set) var loggedSets: [LoggedSet] = []
    @Published private(set) var isRepeat: Bool = false

    /// True once `finish` has saved this session — `workout`/
    /// `completedExerciseIds`/`loggedSets` deliberately stay populated
    /// after that (WorkoutTabView keeps showing the completed exercise
    /// list and the post-workout report card until the user explicitly
    /// starts a new session), but `isActive` flips false so a *different*
    /// surface — Coach chat, most concretely — knows there's nothing left
    /// to log into. Only `discard()` or a new `start()` actually clears
    /// the data.
    @Published private(set) var isFinished: Bool = false

    /// A frozen pre-session baseline (loaded once when the workout becomes
    /// active), so a freshly logged set only ever competes against what
    /// was already true walking in — never against something logged
    /// minutes earlier in this same session. See `isPersonalRecord`.
    @Published private(set) var personalBests: [String: InsightsEngine.PersonalBest] = [:]

    /// The rest timer — previously WorkoutTabView's own private @State,
    /// moved here so Coach chat's start_timer action shows up in the same
    /// countdown banner the Workout tab already renders, rather than
    /// starting a timer nobody but chat can see. `restTimerTotalSecs` is
    /// only meaningful while `restTimerEndDate` is non-nil.
    @Published private(set) var restTimerEndDate: Date?
    @Published private(set) var restTimerTotalSecs: Int = 0

    var isActive: Bool { workout != nil && !isFinished }

    // MARK: - Lifecycle

    /// Starts a new in-progress session — called by WorkoutTabView's own
    /// "Generate" button, by Coach chat's build_workout action, and by
    /// "Repeat This Workout" from a past session's detail view. Whichever
    /// surface calls this, every other surface sees the same workout next
    /// time it reads `workout`, no separate hand-off needed.
    func start(_ workout: GeneratedWorkout, isRepeat: Bool = false) {
        self.workout = workout
        self.isRepeat = isRepeat
        completedExerciseIds = []
        loggedSets = []
        isFinished = false
        personalBests = [:]
    }

    /// Loaded once per session — a wide-enough history window to have a
    /// real shot at every exercise's true best. Deliberately not
    /// refreshed as sets get logged this session; see `isPersonalRecord`.
    func loadPersonalBests(userId: String) async {
        guard let sessions = try? await ForzeeDataService.shared.fetchSessionHistory(userId: userId, limit: 200) else {
            return
        }
        personalBests = InsightsEngine.personalBests(sessions: sessions)
    }

    /// The final save — always succeeds locally regardless of connectivity
    /// (see SyncManager), same guarantee `saveCompletedWorkout` always had.
    /// Flips `isFinished` on success but deliberately leaves `workout`/
    /// `completedExerciseIds`/`loggedSets` in place — WorkoutTabView's
    /// "Session saved" card keeps showing the completed exercise list and
    /// the post-workout report using this same data. `discard()` (via
    /// "Start a New Workout") is what actually clears it.
    @discardableResult
    func finish(userId: String, feedback: SessionFeedback) async throws -> FinishedSession {
        guard let workout, !isFinished else { throw WorkoutSessionError.noActiveSession }

        let completedNames = workout.exercises
            .filter { completedExerciseIds.contains($0.id) }
            .map(\.name)

        try await ForzeeDataService.shared.saveCompletedWorkout(
            workout,
            completedExerciseIds: completedExerciseIds,
            loggedSets: loggedSets,
            feedback: feedback,
            userId: userId,
            isRepeat: isRepeat
        )

        isFinished = true
        return FinishedSession(workout: workout, completedExerciseNames: completedNames)
    }

    /// Clears the session entirely — "Discard & Start Over" on an
    /// in-progress session, or "Start a New Workout" after `finish` has
    /// already saved one. Any UI-only state (rest timer, error banners,
    /// etc.) is the caller's own to reset; this only clears session data.
    func discard() {
        workout = nil
        isRepeat = false
        completedExerciseIds = []
        loggedSets = []
        isFinished = false
        personalBests = [:]
        cancelRestTimer()
    }

    // MARK: - Rest Timer

    /// Starts (or restarts) the rest timer — called after logging a set,
    /// same as always, or directly from Coach chat's start_timer action.
    /// Either way it's the same countdown, visible wherever
    /// RestTimerBanner is shown.
    func startRestTimer(seconds: Int) {
        guard seconds > 0 else { return }
        restTimerTotalSecs = seconds
        restTimerEndDate = Date().addingTimeInterval(TimeInterval(seconds))
        NotificationManager.shared.scheduleRestTimerAlert(seconds: seconds)
    }

    func cancelRestTimer() {
        restTimerEndDate = nil
        NotificationManager.shared.cancelRestTimerAlert()
    }

    // MARK: - Exercises

    /// Appends a manually-added exercise mid-workout — the Add Exercise
    /// sheet's only write.
    func addExercise(_ exercise: WorkoutExercise) {
        workout?.exercises.append(exercise)
    }

    /// Removes an exercise from the workout entirely — distinct from
    /// completing or skipping it. No manual UI triggers this yet (there's
    /// no remove gesture in WorkoutTabView today), but it lives here
    /// rather than ad hoc in the chat action executor so one could be
    /// added later against this exact same method. Drops any logged sets
    /// for it too, so a re-added exercise of the same name never inherits
    /// stale sets.
    @discardableResult
    func removeExercise(_ exerciseId: UUID) -> WorkoutExercise? {
        guard let index = workout?.exercises.firstIndex(where: { $0.id == exerciseId }) else { return nil }
        let removed = workout!.exercises.remove(at: index)
        loggedSets.removeAll { $0.exerciseId == exerciseId }
        completedExerciseIds.remove(exerciseId)
        return removed
    }

    /// Marks the CURRENT exercise complete with no sets behind it — the
    /// same operation the tap-to-complete checkbox already performs when
    /// tapped on an incomplete exercise (see `toggleExerciseComplete`),
    /// just resolved contextually instead of needing a specific exercise
    /// tapped. Nil when every exercise is already complete.
    @discardableResult
    func skipCurrentExercise() -> WorkoutExercise? {
        guard let exercise = currentExercise else { return nil }
        completedExerciseIds.insert(exercise.id)
        return exercise
    }

    /// The tap-to-complete checkbox, with no per-set detail behind it —
    /// distinct from a logged set filling up an exercise's prescribed set
    /// count (see `logSet`/`logNextSet`), which marks it complete on its
    /// own. Returns whether the exercise is now complete, so the caller
    /// can decide whether to fetch a companion comment — that's a
    /// WorkoutTabView-specific reaction, not session data.
    @discardableResult
    func toggleExerciseComplete(_ exerciseId: UUID) -> Bool {
        if completedExerciseIds.contains(exerciseId) {
            completedExerciseIds.remove(exerciseId)
            return false
        }
        completedExerciseIds.insert(exerciseId)
        return true
    }

    // MARK: - Sets

    /// The first exercise not yet marked complete, in the workout's own
    /// order — what "log my next set" or "how am I doing" means when
    /// nobody named a specific exercise. Nil once everything is done.
    var currentExercise: WorkoutExercise? {
        workout?.exercises.first { !completedExerciseIds.contains($0.id) }
    }

    func sets(for exerciseId: UUID) -> [LoggedSet] {
        loggedSets.filter { $0.exerciseId == exerciseId }.sorted { $0.setNumber < $1.setNumber }
    }

    /// Explicit set logging — exercise and set number both known, the
    /// manual per-set editor's only write. Upserts by (exercise,
    /// setNumber) so editing an already-logged set overwrites it rather
    /// than duplicating.
    @discardableResult
    func logSet(
        exerciseId: UUID,
        setNumber: Int,
        weight: Double?,
        unit: WeightUnit,
        reps: Int?,
        restSecs: Int?
    ) -> LogSetOutcome? {
        guard let exercise = workout?.exercises.first(where: { $0.id == exerciseId }) else { return nil }

        if let index = loggedSets.firstIndex(where: { $0.exerciseId == exerciseId && $0.setNumber == setNumber }) {
            loggedSets[index].weightValue = weight
            loggedSets[index].weightUnit = weight == nil ? nil : unit
            loggedSets[index].reps = reps
            loggedSets[index].restSecs = restSecs
        } else {
            loggedSets.append(LoggedSet(
                exerciseId: exerciseId,
                setNumber: setNumber,
                weightValue: weight,
                weightUnit: weight == nil ? nil : unit,
                reps: reps,
                restSecs: restSecs
            ))
        }

        let justCompleted = markCompleteIfFilled(exercise)

        return LogSetOutcome(
            exercise: exercise,
            setNumber: setNumber,
            weightValue: weight,
            weightUnit: weight == nil ? nil : unit,
            reps: reps,
            restSecs: restSecs ?? exercise.restSecs,
            exerciseJustCompleted: justCompleted
        )
    }

    /// Contextual set logging — voice ("mark a set complete, 135, 8 reps")
    /// and Coach chat's log_set action both go through this instead of
    /// naming an exercise/set number themselves: it resolves against
    /// `currentExercise` and the next set number on its own. "Same as
    /// previous" and the prescribed-weight fallback are resolved here,
    /// once, rather than trusted blind from whatever extracted the raw
    /// numbers — this is the data that gets saved. Nil when every
    /// exercise is already complete — there's nothing to log against.
    @discardableResult
    func logNextSet(weightValue: Double?, weightUnit: WeightUnit?, reps: Int?, sameAsPrevious: Bool) -> LogSetOutcome? {
        guard let exercise = currentExercise else { return nil }

        let existing = sets(for: exercise.id)
        let setNumber = existing.count + 1

        var weightValue = weightValue
        var weightUnit = weightUnit
        var reps = reps

        if sameAsPrevious, let last = existing.last {
            weightValue = weightValue ?? last.weightValue
            weightUnit = weightUnit ?? last.weightUnit
            reps = reps ?? last.reps
        }
        if weightValue == nil, let prescribed = exercise.weightKg {
            weightValue = prescribed
            weightUnit = .kg
        }

        loggedSets.append(LoggedSet(
            exerciseId: exercise.id,
            setNumber: setNumber,
            weightValue: weightValue,
            weightUnit: weightUnit,
            reps: reps
        ))

        let justCompleted = markCompleteIfFilled(exercise)

        return LogSetOutcome(
            exercise: exercise,
            setNumber: setNumber,
            weightValue: weightValue,
            weightUnit: weightUnit,
            reps: reps,
            restSecs: exercise.restSecs,
            exerciseJustCompleted: justCompleted
        )
    }

    func removeSet(exerciseId: UUID, setNumber: Int) {
        loggedSets.removeAll { $0.exerciseId == exerciseId && $0.setNumber == setNumber }
        completedExerciseIds.remove(exerciseId)
    }

    /// Marks an exercise complete once its logged sets reach its
    /// prescribed count — shared by both logSet and logNextSet so
    /// "finishing the last set completes the exercise" only has one
    /// implementation. A no-op (returns false) if already complete.
    private func markCompleteIfFilled(_ exercise: WorkoutExercise) -> Bool {
        guard !completedExerciseIds.contains(exercise.id) else { return false }
        guard sets(for: exercise.id).count >= exercise.sets else { return false }
        completedExerciseIds.insert(exercise.id)
        return true
    }

    // MARK: - Voice / Chat Context

    /// A compact snapshot of where things stand, handed to Claude so it
    /// can resolve "same as previous" / "what's next" / "how am I doing"
    /// against real state instead of guessing — the same shape voice mode
    /// has always used, now available to Coach chat too.
    func currentContext() -> WorkoutVoiceState {
        let totalExercises = workout?.exercises.count ?? 0

        guard let exercise = currentExercise else {
            return WorkoutVoiceState(
                currentExerciseName: nil,
                currentExercisePrescription: nil,
                setsLoggedForCurrent: 0,
                totalSetsForCurrent: nil,
                lastLoggedSetDescription: nil,
                remainingExerciseNames: [],
                totalExercises: totalExercises,
                completedExercises: completedExerciseIds.count
            )
        }

        let existing = sets(for: exercise.id)
        let remaining = workout?.exercises
            .filter { $0.id != exercise.id && !completedExerciseIds.contains($0.id) }
            .map(\.name) ?? []

        return WorkoutVoiceState(
            currentExerciseName: exercise.name,
            currentExercisePrescription: "\(exercise.sets) sets of \(exercise.reps)",
            setsLoggedForCurrent: existing.count,
            totalSetsForCurrent: exercise.sets,
            lastLoggedSetDescription: existing.last.map(Self.describe),
            remainingExerciseNames: remaining,
            totalExercises: totalExercises,
            completedExercises: completedExerciseIds.count
        )
    }

    private static func describe(_ set: LoggedSet) -> String {
        var text = ""
        if let weight = set.weightValue, let unit = set.weightUnit {
            text = "\(formatted(weight)) \(unit.spokenName)"
        }
        if let reps = set.reps {
            text += text.isEmpty ? "\(reps) reps" : ", \(reps) reps"
        }
        return text.isEmpty ? "no weight or reps recorded" : text
    }

    private static func formatted(_ value: Double) -> String {
        value.truncatingRemainder(dividingBy: 1) == 0 ? String(Int(value)) : String(format: "%.1f", value)
    }

    // MARK: - PR Detection

    /// Whether a freshly logged set beats `personalBests` for this
    /// exercise — pure comparison, no state mutation. The caller (a view
    /// showing a toast, Kai adding a coaching_note) decides what to do
    /// with the answer.
    func isPersonalRecord(exerciseName: String, weight: Double, unit: WeightUnit, reps: Int) -> Bool {
        guard weight > 0, reps > 0, let best = personalBests[exerciseName] else { return false }
        let weightKg = unit == .kg ? weight : weight * 0.45359237
        return weightKg > best.weightKg || (weightKg == best.weightKg && reps > best.reps)
    }
}

// MARK: - LogSetOutcome

/// What a logSet/logNextSet call actually did — enough for a caller to
/// drive its own side effects (starting a rest timer, checking for a PR,
/// fetching a companion comment, speaking a confirmation) without needing
/// to re-derive any of it from state.
struct LogSetOutcome {
    let exercise: WorkoutExercise
    let setNumber: Int
    let weightValue: Double?
    let weightUnit: WeightUnit?
    let reps: Int?
    let restSecs: Int?
    let exerciseJustCompleted: Bool
}

// MARK: - FinishedSession

/// What `finish` saved — a caller uses this to request the post-workout
/// AI report without needing to have held onto the workout itself.
struct FinishedSession {
    let workout: GeneratedWorkout
    let completedExerciseNames: [String]
}

// MARK: - WorkoutSessionError

enum WorkoutSessionError: LocalizedError {
    case noActiveSession

    var errorDescription: String? {
        switch self {
        case .noActiveSession: return "There's no workout in progress to finish."
        }
    }
}
