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
// ============================================================

import Foundation

/// What running an action actually did — a build_workout starts a real
/// GeneratedWorkout session in WorkoutSessionManager (nothing about the
/// chat message itself changes); a replace_exercise instead mutates the
/// SAME message's own workout block, so the caller needs the updated
/// CoachResponse back to re-store against that message; a log_set writes
/// a real set into whatever session is active, same as WorkoutTabView's
/// own manual entry or voice mode would. `.none` covers "not permitted"
/// and "not implemented" alike — the caller doesn't need to tell those apart.
enum CoachActionOutcome {
    case builtWorkout(GeneratedWorkout)
    case updatedResponse(CoachResponse)
    case loggedSet(LogSetOutcome)
    case none
}

@MainActor
enum CoachActionExecutor {

    static func execute(_ action: CoachAction, from response: CoachResponse) -> CoachActionOutcome {
        guard CoachResponseValidator.isPermitted(action, in: response.blocks) else { return .none }

        switch action.type {
        case .buildWorkout:
            return buildWorkout(from: response)
        case .replaceExercise:
            return replaceExercise(action, in: response)
        case .logSet:
            return logSet(action)
        case .startWorkout, .modifyWorkout, .skipExercise,
             .startTimer, .finishWorkout, .showExercise, .viewProgress, .unknown:
            // isPermitted already excludes all of these — unreachable in
            // practice, kept explicit rather than a `default:` so adding a
            // new CoachActionType case forces a decision here too.
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

    private static func firstWorkoutBlock(in blocks: [CoachBlock]) -> WorkoutBlock? {
        for block in blocks {
            if case .workout(let w) = block { return w }
        }
        return nil
    }
}
