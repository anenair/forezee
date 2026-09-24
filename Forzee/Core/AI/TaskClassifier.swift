// ============================================================
// TaskClassifier.swift
// Forzee — Core/AI
//
// Decides which Claude model to route a task to.
//
// Routing table:
//   Sonnet 5 → everything that isn't a generation: coaching chat,
//              logging, confirmations, simple Q&A, notifications,
//              daily briefing, gym companion, voice commands,
//              skills. Thinking off (see KaiModel.reasoningFields),
//              so short tasks stay fast.
//   Opus 5.5 → workout generation, workout report, weekly read
//              (low-volume calls where output quality matters most)
//
// Haiku 4.5 used to take the short tasks; it was dropped ahead of
// its retirement window (not before 2026-10-15).
// ============================================================

import Foundation

final class TaskClassifier {

    // MARK: - Classification

    /// Classify a user message and return the appropriate model.
    /// Always Sonnet today — kept as the one place chat routing is
    /// decided, so a cheaper tier for simple messages can come back here.
    func classify(message: String, context: UserContextSnapshot) -> KaiModel {
        .sonnet
    }

    /// Classify a task type enum directly (used for non-chat tasks).
    func classify(taskType: KaiTaskType) -> KaiModel {
        switch taskType {
        case .chatMessage:          return .sonnet  // Coaching chat — conversational depth
        case .workoutGeneration:    return .opus    // Low volume, plan quality is the product
        case .workoutReport:        return .opus    // Post-workout report — quality + format reliability
        case .periodization:        return .sonnet
        case .logging:              return .sonnet
        case .confirmation:         return .sonnet
        case .simpleQA:             return .sonnet
        case .notification:         return .sonnet
        case .dailyBriefing:        return .sonnet
        case .gymCompanionComment:  return .sonnet  // Live in-workout remarks — short, thinking off
        }
    }
}

// MARK: - KaiTaskType

/// All task types Kai can perform. Used for model routing and usage tracking.
enum KaiTaskType: String, Codable {
    // Longer tasks
    case chatMessage       = "chat_message"
    case workoutGeneration = "workout_generation"
    case workoutReport     = "workout_report"
    // periodization (plan_deload_week) is anticipated but not yet built as
    // either a KaiEngine method or a skill — kept here so the model-routing
    // table already has an answer for it whenever it lands.
    case periodization     = "periodization"

    // Short tasks
    case logging             = "logging"
    case confirmation        = "confirmation"
    case simpleQA            = "simple_qa"
    case notification        = "notification"
    case dailyBriefing       = "daily_briefing"
    case gymCompanionComment = "gym_companion_comment"

    // workout_voice_command, recovery_advice, and insight_generation used
    // to be cases here — all now run through the generic skills framework
    // (KaiEngine.run(skill:) / discoverAndRunSkill: workout_voice_command,
    // recovery_check, explain_insight) and are tracked under their bundled
    // skill's own name string instead (see Resources/Skills/,
    // UsageGate.recordUsage(taskType: String, ...)). A new skill needs
    // nothing added to this enum to be tracked. ("workout_extraction" was
    // a fourth such skill, extract_workout — removed along with the chat
    // extraction method it backed once Coach chat moved to the typed
    // CoachResponse protocol, see Core/AI/CoachProtocol.)
}
