// ============================================================
// WorkoutVoiceCommandPrompt.swift
// Forzee — Core/AI
//
// Real LLM understanding of mid-workout voice commands — no local
// pattern matching. The tool schema and prompt wording that used
// to live here as hand-written Swift now live in
// Resources/Skills/workout_voice_command.md instead (see
// KaiEngine.interpretWorkoutVoiceCommand, which runs it through
// the generic skills framework). What's left here is state Swift
// still owns: the WorkoutVoiceState snapshot, the conditional
// formatting that turns it into the skill's {{workout_state}}
// placeholder, and the decoded result type.
//
// Haiku, not Sonnet: this fires mid-set, so speed matters, and
// intent classification + number extraction doesn't need Sonnet's
// depth. Genuinely open-ended questions get escalated to a real
// KaiEngine.chat (Sonnet) call by WorkoutTabView when action == "chat".
// ============================================================

import Foundation

enum WorkoutVoiceCommandPrompt {

    /// Renders the conditional "Workout state:" block the skill's prompt
    /// template fills into its {{workout_state}} placeholder. Kept in Swift
    /// rather than the .md file because it branches on live state
    /// (current exercise present or not, a last-logged set or not) — logic
    /// a flat placeholder template can't express, only the value it's
    /// handed. The skill file supplies everything static around it.
    static func stateBlock(_ state: WorkoutVoiceState) -> String {
        var lines: [String] = []

        if let name = state.currentExerciseName {
            lines.append("- Current exercise: \(name) (\(state.currentExercisePrescription ?? ""))")
            lines.append("- Sets logged so far on this exercise: \(state.setsLoggedForCurrent) of \(state.totalSetsForCurrent ?? 0)")
            if let last = state.lastLoggedSetDescription {
                lines.append("- Last logged set on this exercise: \(last)")
            } else {
                lines.append("- No sets logged yet on this exercise.")
            }
        } else {
            lines.append("- Every exercise in this workout is already complete.")
        }

        if !state.remainingExerciseNames.isEmpty {
            lines.append("- Remaining exercises after the current one: \(state.remainingExerciseNames.joined(separator: ", "))")
        }
        lines.append("- Overall: \(state.completedExercises) of \(state.totalExercises) exercises completed.")

        return lines.joined(separator: "\n")
    }
}

// MARK: - WorkoutVoiceState

/// A compact snapshot of the in-progress workout, handed to Claude so it
/// can resolve "same as previous," "what's next," and "how am I doing"
/// against real state rather than guessing.
struct WorkoutVoiceState {
    let currentExerciseName: String?
    let currentExercisePrescription: String?
    let setsLoggedForCurrent: Int
    let totalSetsForCurrent: Int?
    let lastLoggedSetDescription: String?
    let remainingExerciseNames: [String]
    let totalExercises: Int
    let completedExercises: Int
}

// MARK: - WorkoutVoiceCommandResult

struct WorkoutVoiceCommandResult {
    enum Action: String {
        case logSet = "log_set"
        case nextExercise = "next_exercise"
        case progress
        case chat
    }

    let action: Action
    let weightValue: Double?
    let weightUnit: WeightUnit?
    let reps: Int?
    let sameAsPrevious: Bool
    let spokenReply: String

    init(from input: [String: Any]) {
        action = Action(rawValue: input["action"] as? String ?? "") ?? .chat
        weightValue = Self.doubleValue(input["weight_value"])
        weightUnit = (input["weight_unit"] as? String).flatMap(WeightUnit.init(rawValue:))
        reps = Self.intValue(input["reps"])
        sameAsPrevious = input["same_as_previous"] as? Bool ?? false
        spokenReply = input["spoken_reply"] as? String ?? ""
    }

    private static func doubleValue(_ any: Any?) -> Double? {
        if let d = any as? Double { return d }
        if let i = any as? Int { return Double(i) }
        if let n = any as? NSNumber { return n.doubleValue }
        return nil
    }

    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
    }
}
