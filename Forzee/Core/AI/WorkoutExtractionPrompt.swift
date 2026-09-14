// ============================================================
// WorkoutExtractionPrompt.swift
// Forzee — Core/AI
//
// Turns a chat conversation into a structured workout — the
// "Build Workout" button in Coach chat. Real LLM understanding
// of what was actually negotiated (exercises added/removed,
// duration changed, etc.), not pattern matching on keywords.
//
// The tool schema and prompt wording that used to live here as
// hand-written Swift now live in Resources/Skills/extract_workout.md
// instead (see KaiEngine.extractWorkoutFromChat, which runs it
// through discoverAndRunSkill — the model itself decides whether
// the conversation has a real plan, rather than a forced tool call
// relying on a found_plan escape-hatch field to say so). What's
// left here is the error case surfaced when Claude did find a plan
// but its structured output didn't decode.
// ============================================================

import Foundation

// MARK: - WorkoutExtractionError

enum WorkoutExtractionError: LocalizedError {
    case incompletePlan

    var errorDescription: String? {
        "Found a plan but couldn't pin down every detail — try asking Kai to summarize the full exercise list in one message, then build again."
    }
}
