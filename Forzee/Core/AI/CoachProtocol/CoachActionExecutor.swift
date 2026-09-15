// ============================================================
// CoachActionExecutor.swift
// Forzee — Core/AI/CoachProtocol
//
// Executes a CoachAction the user actually tapped — the domain
// layer's side of "never blindly execute an arbitrary LLM-provided
// action." CoachResponseValidator.isPermitted already decided
// whether an action is real before it was ever rendered as a
// button (see CoachActionRow); this is where a permitted action
// actually happens. Nothing here trusts the LLM further than that
// one decision already made.
//
// Every action that touches the in-progress workout goes through
// WorkoutSessionManager — the same interface WorkoutTabView's own
// manual entry and voice mode use — so a set logged, an exercise
// skipped, or a workout finished from chat is indistinguishable
// from doing the same thing by hand or by voice. Nothing here
// duplicates that resolution logic.
// ============================================================

import Foundation

/// What running an action actually did. build_workout/start_workout both
/// start a real session in WorkoutSessionManager (the caller distinguishes
/// them only by label — the app doesn't care which surface a session came
/// from); replace_exercise instead mutates the SAME message's own workout
/// block, so the caller needs the updated CoachResponse back to re-store
/// against that message. `.none` covers "not permitted" and "not
/// implemented" alike — the caller doesn't need to tell those apart.
enum CoachActionOutcome {
    case builtWorkout(GeneratedWorkout)
    case updatedResponse(CoachResponse)
    case loggedSet(LogSetOutcome)
    case startedWorkout(GeneratedWorkout)
    case removedExercise(WorkoutExercise)
    case skippedExercise(WorkoutExercise)
    case startedTimer(seconds: Int)
    case finishedWorkout(FinishedSession)
    case showExercise(name: String)
    case switchedTab(AppTab)
    case none
}

@MainActor
enum CoachActionExecutor {

    static func execute(_ action: CoachAction, from response: CoachResponse, userId: String) async -> CoachActionOutcome {
        guard CoachResponseValidator.isPermitted(action, in: response.blocks) else { return .none }

        switch action.type {
        case .buildWorkout:
            return buildWorkout(from: response)
        case .replaceExercise:
            return replaceExercise(action, in: response)
        case .logSet:
            return logSet(action)
        case .startWorkout:
            return await startWorkout(action, userId: userId)
        case .modifyWorkout:
            return modifyWorkout(action)
        case .skipExercise:
            return skipExercise()
        case .startTimer:
            return startTimer(action)
        case .finishWorkout:
            return await finishWorkout(userId: userId)
        case .showExercise:
            return showExercise(action)
        case .viewProgress:
            return .switchedTab(.progress)
        case .unknown:
            // isPermitted already excludes this — unreachable in practice.
            return .none
        }
    }

    /// Converts the SAME workout block already rendered in this response
    /// into a real GeneratedWorkout via WorkoutBuilder, and starts it in
    /// WorkoutSessionManager exactly like the Workout tab's own Generate
    /// button already does — so either path lands the user on the same
    /// in-progress session. No second LLM call needed: the structured
    /// block IS the proposal, nothing needs re-extracting from prose the
    /// way the old chat-based "Build Workout" flow had to.
    private static func buildWorkout(from response: CoachResponse) -> CoachActionOutcome {
        guard let workoutBlock = firstWorkoutBlock(in: response.blocks) else { return .none }
        let workout = WorkoutBuilder.build(from: workoutBlock.workout)
        WorkoutSessionManager.shared.start(workout)
        return .builtWorkout(workout)
    }

    /// Swaps one exercise's NAME in the proposal's own workout block —
    /// nothing is persisted or built by this; it just updates what the
    /// chat message displays, the same way editing a draft doesn't need
    /// its own confirmation once the confirmation block itself already
    /// asked. The replacement keeps the original's sets/reps/rest exactly
    /// as prescribed (only the exercise identity changes); if the user
    /// wants a materially different exercise, Kai builds it fresh into a
    /// new workout block on the next turn rather than this action trying
    /// to guess new numbers on its own.
    private static func replaceExercise(_ action: CoachAction, in response: CoachResponse) -> CoachActionOutcome {
        guard let exerciseName = action.payload?["exerciseName"],
              let replacementName = action.payload?["replacementName"] else { return .none }

        guard let blockIndex = response.blocks.firstIndex(where: { block -> Bool in
            guard case .workout(let w) = block else { return false }
            return w.workout.exercises.contains { $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame }
        }), case .workout(var workoutBlock) = response.blocks[blockIndex] else { return .none }

        guard let exerciseIndex = workoutBlock.workout.exercises.firstIndex(where: {
            $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame
        }) else { return .none }

        workoutBlock.workout.exercises[exerciseIndex].name = replacementName
        // The old exerciseId (if any) named the exercise being removed —
        // never carry it forward onto a different exercise. WorkoutBuilder
        // re-resolves the new name against ExerciseCatalog when this is
        // eventually built.
        workoutBlock.workout.exercises[exerciseIndex].exerciseId = nil

        var updatedBlocks = response.blocks
        updatedBlocks[blockIndex] = .workout(workoutBlock)

        let updated = CoachResponse(
            protocolVersion: response.protocolVersion,
            messageId: response.messageId,
            blocks: updatedBlocks,
            actions: nil, // the swap is done — nothing left to confirm on this message
            metadata: response.metadata
        )
        return .updatedResponse(updated)
    }

    /// Logs a real set into whatever session WorkoutSessionManager already
    /// has active — always against the CURRENT exercise (isPermitted
    /// already confirmed a session exists), never a named one. Uses the
    /// exact same logNextSet resolution ("same as previous," the
    /// prescribed-weight fallback, marking the exercise complete on the
    /// last set) that WorkoutTabView's own voice mode already relies on —
    /// this is genuinely the same operation, just triggered from Coach
    /// chat instead of a mic.
    private static func logSet(_ action: CoachAction) -> CoachActionOutcome {
        let payload = action.payload ?? [:]
        let reps = payload["reps"].flatMap(Int.init)
        let weightValue = payload["weight"].flatMap(Double.init)
        let weightUnit: WeightUnit? = weightValue == nil ? nil : (payload["weightUnit"].flatMap(WeightUnit.init(rawValue:)) ?? .lbs)
        let sameAsPrevious = payload["sameAsPrevious"] == "true"

        guard let outcome = WorkoutSessionManager.shared.logNextSet(
            weightValue: weightValue,
            weightUnit: weightUnit,
            reps: reps,
            sameAsPrevious: sameAsPrevious
        ) else { return .none }

        return .loggedSet(outcome)
    }

    /// Starts a repeat of a NAMED past workout — the chat equivalent of
    /// tapping "Repeat This Workout" on a past session's detail view
    /// (WorkoutDetailView.repeatWorkout), just resolved by name instead of
    /// the user picking from a list. isPermitted already confirmed no
    /// session is currently active, so this never silently discards one.
    /// Searches a wide-enough window of recent sessions (matching
    /// WorkoutSessionManager.loadPersonalBests' own limit) for the most
    /// recent one whose workout name contains what the user said.
    private static func startWorkout(_ action: CoachAction, userId: String) async -> CoachActionOutcome {
        guard let workoutName = action.payload?["workoutName"] else { return .none }

        guard let sessions = try? await ForzeeDataService.shared.fetchSessionHistory(userId: userId, limit: 200),
              let match = sessions.first(where: {
                  $0.workout?.name.localizedCaseInsensitiveContains(workoutName) == true
              }),
              let workoutId = match.workoutId,
              let workoutUUID = UUID(uuidString: workoutId),
              let info = match.workout,
              let exercises = info.exercises else { return .none }

        let workout = GeneratedWorkout(
            id: workoutUUID,
            name: info.name,
            workoutType: info.workoutType,
            estimatedDurationMins: info.estimatedDurationMins ?? 45,
            exercises: exercises,
            generatedAt: info.generatedAt ?? .now
        )
        WorkoutSessionManager.shared.start(workout, isRepeat: true)
        return .startedWorkout(workout)
    }

    /// Removes a named exercise from the current session — isPermitted
    /// already confirmed it's actually there.
    private static func modifyWorkout(_ action: CoachAction) -> CoachActionOutcome {
        guard let exerciseName = action.payload?["exerciseName"],
              let exerciseId = WorkoutSessionManager.shared.workout?.exercises.first(where: {
                  $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame
              })?.id,
              let removed = WorkoutSessionManager.shared.removeExercise(exerciseId) else { return .none }
        return .removedExercise(removed)
    }

    /// Marks the CURRENT exercise done with no sets behind it — the exact
    /// same operation as tapping its checkbox while incomplete.
    private static func skipExercise() -> CoachActionOutcome {
        guard let exercise = WorkoutSessionManager.shared.skipCurrentExercise() else { return .none }
        return .skippedExercise(exercise)
    }

    private static func startTimer(_ action: CoachAction) -> CoachActionOutcome {
        guard let seconds = (action.payload?["seconds"]).flatMap(Int.init) else { return .none }
        WorkoutSessionManager.shared.startRestTimer(seconds: seconds)
        return .startedTimer(seconds: seconds)
    }

    /// Ends the current session with no feedback captured — the same
    /// operation as tapping "Skip" on the post-workout feedback sheet
    /// (SessionFeedbackSheet). Kai doesn't attempt to extract mood/effort/
    /// notes from the conversation for this v1; that's a real future
    /// enhancement, not a silent gap in what already exists.
    private static func finishWorkout(userId: String) async -> CoachActionOutcome {
        guard let finished = try? await WorkoutSessionManager.shared.finish(userId: userId, feedback: .empty) else {
            return .none
        }
        return .finishedWorkout(finished)
    }

    /// No session needed — this just names which exercise's history to
    /// open, the same sheet the clock-icon button opens from WorkoutTabView.
    private static func showExercise(_ action: CoachAction) -> CoachActionOutcome {
        guard let exerciseName = action.payload?["exerciseName"] else { return .none }
        return .showExercise(name: exerciseName)
    }

    private static func firstWorkoutBlock(in blocks: [CoachBlock]) -> WorkoutBlock? {
        for block in blocks {
            if case .workout(let w) = block { return w }
        }
        return nil
    }
}
