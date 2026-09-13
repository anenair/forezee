// ============================================================
// KaiEngine.swift
// Forzee — Core/AI
//
// The AI coaching brain. All interactions with the Claude API
// flow through this single engine.
//
// Architecture:
//   - KaiEngine owns the API key and HTTP session
//   - TaskClassifier decides which model to use (Haiku vs Sonnet)
//   - ContextBuilder assembles the compressed user context snapshot
//   - UsageGate enforces free-tier limits before any API call
//   - All responses are streamed for a real-time coaching feel
//
// Model routing (enforced by TaskClassifier):
//   - claude-haiku-4-5  → logging, confirmations, simple Q&A, daily briefing
//   - claude-sonnet-4-6 → coaching, workout gen, recovery advice, periodization
//   - Never use Opus.
// ============================================================

import Foundation

// MARK: - KaiEngine

@MainActor
final class KaiEngine: ObservableObject {

    // MARK: - Shared Instance

    static let shared = KaiEngine()

    // MARK: - Published State

    /// True while a streaming API response is in flight.
    @Published var isResponding: Bool = false

    // MARK: - Dependencies

    private let contextBuilder: ContextBuilder
    private let taskClassifier: TaskClassifier
    private let usageGate: UsageGate
    private let apiClient: ClaudeAPIClient

    // MARK: - Init

    private init() {
        self.contextBuilder = ContextBuilder()
        self.taskClassifier = TaskClassifier()
        self.usageGate = UsageGate()
        self.apiClient = ClaudeAPIClient()
    }

    // MARK: - Public Interface

    /// Send a coaching message from the user and receive a streaming response.
    ///
    /// - Parameters:
    ///   - message: The raw text from the user.
    ///   - userId: The authenticated user's UUID.
    ///   - history: The recent conversation history (last 5 messages + summary).
    ///   - onToken: Called with each streamed token as it arrives.
    ///   - onComplete: Called when the full response is assembled.
    func chat(
        message: String,
        userId: String,
        history: [KaiMessage],
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (KaiMessage) -> Void
    ) async throws {
        // 1. Enforce usage limits for free-tier users
        try await usageGate.checkLimit(userId: userId, taskType: .chatMessage)

        // 2. Build context snapshot
        let context = await contextBuilder.buildSnapshot(userId: userId)

        // 3. Classify task → choose model
        let model = taskClassifier.classify(message: message, context: context)

        // 4. Assemble messages array (system + history + new message)
        let messages = assembleMessages(
            userMessage: message,
            history: history,
            context: context
        )

        // 5. Stream response
        isResponding = true
        defer { isResponding = false }

        let fullResponse = try await apiClient.streamCompletion(
            model: model,
            systemPrompt: KaiSystemPrompt.build(context: context),
            messages: messages,
            onToken: onToken
        )

        // 6. Record usage
        await usageGate.recordUsage(
            userId: userId,
            taskType: .chatMessage,
            model: model,
            inputTokens: messages.estimatedTokenCount,
            outputTokens: fullResponse.estimatedTokenCount
        )

        // 7. Return assembled message
        let responseMessage = KaiMessage(role: .assistant, content: fullResponse)
        onComplete(responseMessage)
    }

    /// Generate an adaptive workout for the user.
    ///
    /// Always uses Sonnet. Requires context snapshot for personalisation.
    func generateWorkout(
        userId: String,
        preferences: WorkoutPreferences? = nil
    ) async throws -> GeneratedWorkout {
        // 1. Gate check
        try await usageGate.checkLimit(userId: userId, taskType: .workoutGeneration)

        // 2. Context snapshot
        let context = await contextBuilder.buildSnapshot(userId: userId)

        // 3. Always Sonnet for workout generation
        let model = KaiModel.sonnet

        // 4. Build generation prompt
        let prompt = WorkoutGenerationPrompt.build(context: context, preferences: preferences)

        // 5. Request structured workout JSON
        let response = try await apiClient.complete(
            model: model,
            systemPrompt: KaiSystemPrompt.build(context: context),
            userMessage: prompt
        )

        // 6. Parse response into GeneratedWorkout
        let workout = try WorkoutParser.parse(response: response, userId: userId, context: context)

        // 7. Record usage
        await usageGate.recordUsage(
            userId: userId,
            taskType: .workoutGeneration,
            model: model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: response.estimatedTokenCount
        )

        return workout
    }

    /// Generate the user's daily morning briefing (always free).
    ///
    /// Uses Haiku — fast, cheap, sufficient for a daily summary.
    func generateDailyBriefing(userId: String) async throws -> String {
        let context = await contextBuilder.buildSnapshot(userId: userId)
        let model = KaiModel.haiku

        let prompt = DailyBriefingPrompt.build(context: context)

        let response = try await apiClient.complete(
            model: model,
            systemPrompt: KaiSystemPrompt.build(context: context),
            userMessage: prompt
        )

        await usageGate.recordUsage(
            userId: userId,
            taskType: .dailyBriefing,
            model: model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: response.estimatedTokenCount
        )

        return response
    }

    /// A short, live remark fired when the user checks off an exercise mid-workout.
    /// Haiku, no context snapshot — this needs to land while someone's resting
    /// between sets at the gym, not after a HealthKit/EventKit/WeatherKit round-trip.
    func generateGymCompanionComment(
        userId: String,
        exerciseName: String,
        fitnessLevel: String
    ) async throws -> String {
        let model = KaiModel.haiku
        let prompt = GymCompanionCommentPrompt.build(exerciseName: exerciseName, fitnessLevel: fitnessLevel)

        let response = try await apiClient.complete(
            model: model,
            systemPrompt: KaiSystemPrompt.identityOnly,
            userMessage: prompt
        )

        await usageGate.recordUsage(
            userId: userId,
            taskType: .gymCompanionComment,
            model: model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: response.estimatedTokenCount
        )

        return response
    }

    /// Real LLM understanding of a mid-workout voice command — no local
    /// pattern matching. Haiku + tool use classifies the intent and extracts
    /// weight/reps in one call; genuinely open-ended questions come back as
    /// action == .chat for the caller to escalate to a full chat() call.
    /// No context snapshot, same reasoning as the companion comment: this
    /// needs to come back fast, and workout state (not sleep/calendar/weather)
    /// is what actually matters for this decision.
    func interpretWorkoutVoiceCommand(
        userId: String,
        transcript: String,
        state: WorkoutVoiceState
    ) async throws -> WorkoutVoiceCommandResult {
        let model = KaiModel.haiku
        let prompt = WorkoutVoiceCommandPrompt.build(transcript: transcript, state: state)

        let input = try await apiClient.completeWithTool(
            model: model,
            systemPrompt: KaiSystemPrompt.identityOnly,
            userMessage: prompt,
            tool: WorkoutVoiceCommandPrompt.tool
        )
        let result = WorkoutVoiceCommandResult(from: input)

        await usageGate.recordUsage(
            userId: userId,
            taskType: .workoutVoiceCommand,
            model: model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: result.spokenReply.estimatedTokenCount
        )

        return result
    }

    /// A short report after the user finishes a workout — what they actually
    /// did vs. what was prescribed, plus one thing to focus on next time.
    /// Sonnet — needs to reason over the full context snapshot, same as generation.
    func generateWorkoutReport(
        userId: String,
        workout: GeneratedWorkout,
        completedExerciseNames: [String]
    ) async throws -> String {
        try await usageGate.checkLimit(userId: userId, taskType: .workoutReport)

        let context = await contextBuilder.buildSnapshot(userId: userId)
        let model = KaiModel.sonnet
        let prompt = WorkoutReportPrompt.build(
            context: context,
            workout: workout,
            completedExerciseNames: completedExerciseNames
        )

        let response = try await apiClient.complete(
            model: model,
            systemPrompt: KaiSystemPrompt.build(context: context),
            userMessage: prompt
        )

        await usageGate.recordUsage(
            userId: userId,
            taskType: .workoutReport,
            model: model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: response.estimatedTokenCount
        )

        return response
    }

    // MARK: - Private Helpers

    private func assembleMessages(
        userMessage: String,
        history: [KaiMessage],
        context: UserContextSnapshot
    ) -> [KaiMessage] {
        // Keep only last 5 messages from history + the new user message
        // Full conversation history is never sent — only the rolling summary
        // embedded in the context snapshot. Token budget: <2,000 input tokens.
        let recentHistory = Array(history.suffix(5))
        return recentHistory + [KaiMessage(role: .user, content: userMessage)]
    }
}

// MARK: - KaiModel

/// The Claude models Kai is allowed to use.
/// Never use Opus — not needed for this use case.
enum KaiModel: String {
    case haiku  = "claude-haiku-4-5-20251001"
    case sonnet = "claude-sonnet-4-6"
}

// MARK: - KaiMessage

/// A single message in the Kai conversation thread.
struct KaiMessage: Identifiable, Codable, Equatable {
    let id: UUID
    let role: KaiRole
    let content: String
    let createdAt: Date

    init(id: UUID = UUID(), role: KaiRole, content: String, createdAt: Date = .now) {
        self.id = id
        self.role = role
        self.content = content
        self.createdAt = createdAt
    }
}

enum KaiRole: String, Codable {
    case user      = "user"
    case assistant = "assistant"
}

// MARK: - WorkoutPreferences

/// Optional overrides the user can pass when requesting a workout.
struct WorkoutPreferences {
    var durationMinutes: Int?
    var focusMuscleGroups: [String]?
    var equipmentOverride: [String]?
    var intensityOverride: String? // "light" | "moderate" | "hard"
}

// MARK: - String Token Estimation

extension String {
    /// Very rough token estimate for budget tracking only.
    /// Real counts come back from the API usage object.
    var estimatedTokenCount: Int {
        max(1, count / 4)
    }
}

extension [KaiMessage] {
    var estimatedTokenCount: Int {
        map { $0.content.estimatedTokenCount }.reduce(0, +)
    }
}
