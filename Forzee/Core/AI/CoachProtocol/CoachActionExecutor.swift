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

@MainActor
enum CoachActionExecutor {

    /// build_workout is the only action implemented in v1 — it converts
    /// the SAME workout block already rendered in this response into a
    /// real GeneratedWorkout via WorkoutBuilder, and hands it to AppState
    /// exactly like the Workout tab's own Generate button already does.
    /// No second LLM call needed: the structured block IS the proposal,
    /// nothing needs re-extracting from prose the way the old chat-based
    /// "Build Workout" flow had to.
    ///
    /// Returns the built workout on success (so the caller can show a
    /// confirmation naming it) — nil if the action wasn't permitted or
    /// isn't implemented, in which case nothing in AppState changes.
    @discardableResult
    static func execute(_ action: CoachAction, from response: CoachResponse, appState: AppState) -> GeneratedWorkout? {
        guard CoachResponseValidator.isPermitted(action, in: response.blocks) else { return nil }

        switch action.type {
        case .buildWorkout:
            guard let workoutBlock = response.blocks.compactMap({ block -> WorkoutBlock? in
                if case .workout(let w) = block { return w }
                return nil
            }).first else { return nil }

            let workout = WorkoutBuilder.build(from: workoutBlock.workout)
            appState.activeWorkout = workout
            appState.isRepeatWorkout = false
            return workout

        case .startWorkout, .replaceExercise, .modifyWorkout, .logSet, .skipExercise,
             .startTimer, .finishWorkout, .showExercise, .viewProgress, .unknown:
            // isPermitted already excludes all of these — unreachable in
            // practice, kept explicit rather than a `default:` so adding a
            // new CoachActionType case forces a decision here too.
            return nil
        }
    }
}
