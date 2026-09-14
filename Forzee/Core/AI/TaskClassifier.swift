// ============================================================
// TaskClassifier.swift
// Forzee — Core/AI
//
// Decides which Claude model to route a task to.
//
// Rule: use Haiku unless the task genuinely needs Sonnet's
// full reasoning. Every unnecessary Sonnet call costs ~10x more.
//
// Routing table (from PRD / briefing):
//   Haiku  → logging, confirmations, simple Q&A, notifications,
//             daily briefing
//   Sonnet → coaching conversations, workout generation,
//             recovery advice, periodization, insight generation
// ============================================================

import Foundation

final class TaskClassifier {

    // MARK: - Classification

    /// Classify a user message and return the appropriate model.
    func classify(message: String, context: UserContextSnapshot) -> KaiModel {
        if isSimpleTask(message: message) {
            return .haiku
        }
        return .sonnet
    }

    /// Classify a task type enum directly (used for non-chat tasks).
    func classify(taskType: KaiTaskType) -> KaiModel {
        switch taskType {
        case .chatMessage:          return .sonnet  // Coaching chat — conversational depth
        case .workoutGeneration:    return .sonnet
        case .workoutReport:        return .sonnet  // Post-workout report — quality + format reliability
        case .recoveryAdvice:       return .sonnet
        case .periodization:        return .sonnet
        case .insightGeneration:    return .sonnet
        case .logging:              return .haiku
        case .confirmation:         return .haiku
        case .simpleQA:             return .haiku
        case .notification:         return .haiku
        case .dailyBriefing:        return .haiku
        case .gymCompanionComment:  return .haiku  // Live in-workout remarks — speed + cost
        }
    }

    // MARK: - Private

    /// Heuristic check for messages that clearly don't need Sonnet.
    /// Intent: save cost on the ~30% of messages that are simple.
    private func isSimpleTask(message: String) -> Bool {
        let lower = message.lowercased().trimmingCharacters(in: .whitespaces)

        // Very short messages are usually confirmations or acks
        if lower.count < 20 { return true }

        // Logging keywords
        let loggingPatterns = ["logged", "done", "finished", "completed", "skipped", "rest day"]
        if loggingPatterns.contains(where: lower.contains) { return true }

        // Simple yes/no
        let simpleResponses = ["yes", "no", "ok", "okay", "sure", "sounds good", "got it", "thanks"]
        if simpleResponses.contains(where: { lower == $0 || lower.hasPrefix($0 + " ") }) { return true }

        return false
    }
}

// MARK: - KaiTaskType

/// All task types Kai can perform. Used for model routing and usage tracking.
enum KaiTaskType: String, Codable {
    // Sonnet tasks
    case chatMessage       = "chat_message"
    case workoutGeneration = "workout_generation"
    case workoutReport     = "workout_report"
    case recoveryAdvice    = "recovery_advice"
    case periodization     = "periodization"
    case insightGeneration = "insight_generation"

    // Haiku tasks
    case logging             = "logging"
    case confirmation        = "confirmation"
    case simpleQA            = "simple_qa"
    case notification        = "notification"
    case dailyBriefing       = "daily_briefing"
    case gymCompanionComment = "gym_companion_comment"

    // workout_voice_command and workout_extraction used to be cases here —
    // both now run through the generic skills framework (KaiEngine.run(skill:)
    // / discoverAndRunSkill) and are tracked under their bundled skill's own
    // name string instead (see Resources/Skills/, UsageGate.recordUsage(taskType: String, ...)).
    // A new skill needs nothing added to this enum to be tracked.
}
