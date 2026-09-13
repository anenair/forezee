// ============================================================
// WorkoutVoiceCommandPrompt.swift
// Forzee — Core/AI
//
// Real LLM understanding of mid-workout voice commands — no local
// pattern matching. Claude (Haiku, via tool use — see
// ClaudeAPIClient.completeWithTool) both classifies the intent and
// extracts weight/reps in one call, forced into structured output
// via a single tool so the result is always parseable.
//
// Haiku, not Sonnet: this fires mid-set, so speed matters, and
// intent classification + number extraction doesn't need Sonnet's
// depth. Genuinely open-ended questions get escalated to a real
// KaiEngine.chat (Sonnet) call by WorkoutTabView when action == "chat".
// ============================================================

import Foundation

enum WorkoutVoiceCommandPrompt {

    static let tool = ClaudeTool(
        name: "workout_voice_command",
        description: "Interpret a spoken mid-workout command from the user and decide what to do.",
        inputSchema: [
            "type": "object",
            "properties": [
                "action": [
                    "type": "string",
                    "enum": ["log_set", "next_exercise", "progress", "chat"],
                    "description": """
                    log_set: user is reporting a completed set (weight/reps, or \
                    "same as previous", or just "mark a set done"). next_exercise: \
                    asking what to do next. progress: asking how they're doing / \
                    what's left. chat: anything else — an open-ended question that \
                    needs a real coaching answer, not one of the above.
                    """,
                ],
                "weight_value": [
                    "type": "number",
                    "description": "The weight the user said, if any. Omit if not mentioned.",
                ],
                "weight_unit": [
                    "type": "string",
                    "enum": ["lbs", "kg"],
                    "description": "Unit for weight_value. Omit if weight_value is omitted.",
                ],
                "reps": [
                    "type": "integer",
                    "description": "Reps completed, if the user said a number. Omit if not mentioned.",
                ],
                "same_as_previous": [
                    "type": "boolean",
                    "description": "True if the user said something like \"same as last time\" / \"same weight\".",
                ],
                "spoken_reply": [
                    "type": "string",
                    "description": """
                    A short (under 15 words), natural spoken confirmation or answer — \
                    what Kai should say back out loud. Only used directly for log_set/ \
                    next_exercise/progress; ignored for chat (that gets a full answer \
                    elsewhere), but still fill it in with something reasonable.
                    """,
                ],
            ],
            "required": ["action", "same_as_previous", "spoken_reply"],
        ]
    )

    static func build(transcript: String, state: WorkoutVoiceState) -> String {
        var lines = ["The user just said: \"\(transcript)\""]
        lines.append("")
        lines.append("Workout state:")

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
