// ============================================================
// CoachResponseValidator.swift
// Forzee — Core/AI/CoachProtocol
//
// Schema validation (Codable decode — see CoachResponse.from(toolInput:))
// only proves a reply was well-formed JSON matching the tool schema. It
// says nothing about whether the numbers inside make sense — sets = -3,
// reps = 50000, restSeconds = -10, durationSeconds = 0 are all perfectly
// valid JSON. This pass catches that, at the one boundary where an LLM's
// raw output crosses into the application: never trust a decoded value
// just because it decoded.
//
// Deliberately permissive about what to DO with a bad value rather than
// throwing: a workout block with one bad exercise loses that exercise,
// not the whole reply; a response with zero valid blocks still gets
// something back to the user (see `sanitize`'s fallback). This mirrors
// the rest of the app's "never let one bad field sink the whole turn"
// posture — WorkoutExercise's own forgiving decode does the same thing
// for a malformed muscle-group tag.
// ============================================================

import Foundation

@MainActor
enum CoachResponseValidator {

    // MARK: - Limits

    private static let maxSets = 20
    private static let maxReps = 1000
    private static let maxDurationSeconds = 3600
    private static let maxRestSeconds = 900

    // MARK: - Sanitize

    /// Cleans a decoded CoachResponse into one safe to render — drops
    /// individual exercises/blocks that fail domain validation rather
    /// than rejecting the whole reply, and guarantees at least one block
    /// survives (a decode that produced zero usable blocks becomes a
    /// plain apology, never an empty chat bubble). Also drops any action
    /// that isn't actually permitted against the *cleaned* blocks — see
    /// `isPermitted`.
    static func sanitize(_ response: CoachResponse) -> CoachResponse {
        let cleanedBlocks = response.blocks.compactMap(sanitize)
        let finalBlocks = cleanedBlocks.isEmpty
            ? [CoachBlock.text(TextBlock(content: "I couldn't put that together clearly — try asking again."))]
            : cleanedBlocks

        return CoachResponse(
            protocolVersion: response.protocolVersion,
            messageId: response.messageId,
            blocks: finalBlocks,
            actions: response.actions?.filter { isPermitted($0, in: finalBlocks) },
            metadata: response.metadata
        )
    }

    /// nil means "drop this block entirely" — used for a workout block
    /// that ends up with zero valid exercises after cleaning. Every other
    /// block type either has nothing worth validating yet (text,
    /// coaching_note's content is free text) or is architecture-only in
    /// v1 (progress/confirmation) and passes through untouched; `.unknown`
    /// always passes through too — it's not this pass's business to
    /// judge a block type it doesn't understand.
    private static func sanitize(_ block: CoachBlock) -> CoachBlock? {
        switch block {
        case .text, .coachingNote, .progress, .confirmation, .unknown:
            return block
        case .workout(let workoutBlock):
            let validExercises = workoutBlock.workout.exercises.compactMap(sanitize)
            guard !validExercises.isEmpty else { return nil }
            var workout = workoutBlock.workout
            workout.exercises = validExercises
            return .workout(WorkoutBlock(workout: workout))
        }
    }

    private static func sanitize(_ exercise: CoachExercise) -> CoachExercise? {
        guard !exercise.name.trimmingCharacters(in: .whitespaces).isEmpty else { return nil }
        guard let prescription = sanitize(exercise.prescription) else { return nil }
        var cleaned = exercise
        cleaned.prescription = prescription
        return cleaned
    }

    private static func sanitize(_ prescription: ExercisePrescription) -> ExercisePrescription? {
        switch prescription {
        case .reps(var p):
            guard clamp(&p.sets, 1, maxSets), clamp(&p.reps, 1, maxReps) else { return nil }
            if let rest = p.restSeconds { p.restSeconds = max(0, min(rest, maxRestSeconds)) }
            return .reps(p)
        case .duration(var p):
            guard clamp(&p.sets, 1, maxSets), clamp(&p.durationSeconds, 1, maxDurationSeconds) else { return nil }
            if let rest = p.restSeconds { p.restSeconds = max(0, min(rest, maxRestSeconds)) }
            return .duration(p)
        case .repRange(var p):
            guard clamp(&p.sets, 1, maxSets) else { return nil }
            p.repsMin = max(1, min(p.repsMin, maxReps))
            p.repsMax = max(p.repsMin, min(p.repsMax, maxReps))
            if let rest = p.restSeconds { p.restSeconds = max(0, min(rest, maxRestSeconds)) }
            return .repRange(p)
        case .unknown:
            // Not renderable yet, but not invalid either — a prescription
            // type this build doesn't model yet isn't this pass's call to
            // reject.
            return prescription
        }
    }

    /// Clamps `value` into `[low, high]` in place; returns false only when
    /// the ORIGINAL value was nonsensical enough to indicate a bad
    /// generation (<= 0) rather than just an unusually large number worth
    /// quietly clamping down.
    private static func clamp(_ value: inout Int, _ low: Int, _ high: Int) -> Bool {
        guard value > 0 else { return false }
        value = max(low, min(value, high))
        return true
    }

    // MARK: - Action Permissions

    /// The application, not the LLM, decides whether a proposed action is
    /// actually actionable. An action referencing a workout block that
    /// didn't survive sanitization (or was never there) is never
    /// rendered, regardless of what the model included in `actions`.
    static func isPermitted(_ action: CoachAction, in blocks: [CoachBlock]) -> Bool {
        switch action.type {
        case .buildWorkout:
            return blocks.contains { if case .workout = $0 { return true }; return false }
        case .replaceExercise:
            // Requires a real payload naming both sides of the swap, AND
            // the exercise being removed must actually be present in a
            // workout block in this same reply — an action claiming to
            // replace something that isn't there is never rendered,
            // regardless of what the model included.
            guard let exerciseName = action.payload?["exerciseName"],
                  let replacementName = action.payload?["replacementName"],
                  !replacementName.trimmingCharacters(in: .whitespaces).isEmpty else { return false }
            return blocks.contains { block in
                guard case .workout(let workoutBlock) = block else { return false }
                return workoutBlock.workout.exercises.contains {
                    $0.name.caseInsensitiveCompare(exerciseName) == .orderedSame
                }
            }
        case .logSet:
            // Only when a real session is actually in progress AND it
            // still has a current exercise to log into — `isActive` alone
            // covers "not started yet" / "already finished," but not the
            // in-between state where every exercise is already checked
            // off but the session itself hasn't been finished yet (e.g.
            // right after logging the last set of the last exercise).
            // Without this second check, a stale log_set button would
            // silently no-op on tap (WorkoutSessionManager.logNextSet
            // returns nil with nothing else for the app to say) instead of
            // never being offered in the first place. Also requires a real
            // rep count or an explicit "reuse the previous set" — never a
            // bare, numberless action that would leave the manager to guess.
            guard WorkoutSessionManager.shared.isActive,
                  WorkoutSessionManager.shared.currentExercise != nil else { return false }
            // Same "never trust a decoded value just because it decoded"
            // rule as a workout prescription's own reps, reusing the same
            // maxReps bound — a hallucinated rep count is exactly the kind
            // of bad-generation signal this pass exists to catch, and
            // unlike a workout proposal, this one writes straight to real
            // logged history if let through.
            let hasReps = (action.payload?["reps"]).flatMap(Int.init).map { $0 > 0 && $0 <= maxReps } ?? false
            let reusesPrevious = action.payload?["sameAsPrevious"] == "true"
            return hasReps || reusesPrevious
        case .startWorkout, .modifyWorkout, .skipExercise,
             .startTimer, .finishWorkout, .showExercise, .viewProgress:
            // Not implemented yet — see CoachActionExecutor. Permitting an
            // action the executor can't run would render a dead button.
            return false
        case .unknown:
            return false
        }
    }
}
