// ============================================================
// WorkoutExtractionPrompt.swift
// Forzee — Core/AI
//
// Turns a chat conversation into a structured workout — the
// "Build Workout" button in Coach chat. Real LLM understanding
// of what was actually negotiated (exercises added/removed,
// duration changed, etc.), not pattern matching on keywords.
// Forced tool use via ClaudeAPIClient.completeWithTool, same
// pattern as WorkoutVoiceCommandPrompt: foundPlan is the escape
// hatch when the conversation doesn't contain a clear plan yet.
// ============================================================

import Foundation

enum WorkoutExtractionPrompt {

    static let tool = ClaudeTool(
        name: "extract_workout",
        description: "Extract the specific workout plan the coach and user settled on in this conversation, if any.",
        inputSchema: [
            "type": "object",
            "properties": [
                "found_plan": [
                    "type": "boolean",
                    "description": """
                    True only if the conversation contains a specific, buildable workout — \
                    named exercises with sets/reps. False if it's still vague ("something for \
                    my legs") or no workout was discussed at all.
                    """,
                ],
                "name": ["type": "string", "description": "Short workout name, e.g. \"Full Body A\"."],
                "workout_type": [
                    "type": "string",
                    "enum": ["strength", "cardio", "mobility", "hiit", "recovery"],
                ],
                "estimated_duration_mins": ["type": "integer"],
                "coaching_note": [
                    "type": "string",
                    "description": "One or two sentences from Kai on why this fits, shown to the user.",
                ],
                "exercises": [
                    "type": "array",
                    "items": [
                        "type": "object",
                        "properties": [
                            "name": ["type": "string"],
                            "sets": ["type": "integer"],
                            "reps": ["type": "string", "description": "e.g. \"8-12\" or \"10\"."],
                            "weight_kg": ["type": "number", "description": "Omit for bodyweight or user-determined."],
                            "rest_secs": ["type": "integer"],
                            "notes": ["type": "string", "description": "Form cue or modification, if any."],
                        ],
                        "required": ["name", "sets", "reps"],
                    ],
                ],
            ],
            "required": ["found_plan"],
        ]
    )

    /// Only the last N turns matter here — this extracts the latest agreed
    /// plan, not the full history a chat call would need for tone/context.
    static func build(history: [KaiMessage]) -> String {
        let transcript = history.suffix(20)
            .map { "\($0.role == .user ? "User" : "Kai"): \($0.content)" }
            .joined(separator: "\n")

        return """
        Recent conversation between the user and their coach Kai:

        \(transcript)

        Extract the specific workout plan they settled on — the exact exercises, \
        sets, and reps, including any changes the user asked for (added/removed an \
        exercise, different duration, swapped something out). Use the latest version \
        of the plan if it evolved over the conversation, not an earlier draft.
        """
    }
}

// MARK: - WorkoutExtractionError

enum WorkoutExtractionError: LocalizedError {
    case incompletePlan

    var errorDescription: String? {
        "Found a plan but couldn't pin down every detail — try asking Kai to summarize the full exercise list in one message, then build again."
    }
}
