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

        // Persist the user's message now, not after the reply — best-effort,
        // matches the rest of the app's policy of treating chat history as
        // lower-stakes (see SyncManager). Never blocks or fails the chat turn.
        try? await ForzeeDataService.shared.saveMessage(KaiMessage(role: .user, content: message), userId: userId)

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
        try? await ForzeeDataService.shared.saveMessage(responseMessage, userId: userId)
        onComplete(responseMessage)
    }

    /// Restore recent chat history on launch — best-effort, empty on failure.
    func loadRecentHistory(userId: String) async -> [KaiMessage] {
        let stored = (try? await ForzeeDataService.shared.fetchRecentMessages(userId: userId)) ?? []
        return stored.map { $0.toKaiMessage() }
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
    ///
    /// This always needs a structured decision back — never plain prose —
    /// so it goes through the forced single-skill path (`run(skill:)`), not
    /// `discoverAndRunSkill`'s "Claude may decline" one.
    func interpretWorkoutVoiceCommand(
        userId: String,
        transcript: String,
        state: WorkoutVoiceState
    ) async throws -> WorkoutVoiceCommandResult {
        guard let skill = SkillLoader.shared.skill(named: "workout_voice_command") else {
            throw ClaudeAPIError.malformedResponse
        }

        let input = try await run(
            skill: skill,
            placeholders: [
                "transcript": transcript,
                "workout_state": WorkoutVoiceCommandPrompt.stateBlock(state),
            ],
            userId: userId
        )
        return WorkoutVoiceCommandResult(from: input)
    }

    /// Extracts a structured workout from a chat conversation — the "Build
    /// Workout" button in Coach chat. Returns nil if the conversation
    /// genuinely doesn't contain a plan yet — either because Kai's own
    /// found_plan field says so, or because Claude didn't reach for the
    /// extract_workout skill at all (discoverAndRunSkill's "may decline"
    /// case, which is exactly what a vague/no-plan conversation should
    /// produce). Throws if the model reported finding one but its
    /// structured output didn't decode — a distinct case from "no plan,"
    /// surfaced to the user as such rather than the misleading "ask Kai to
    /// lay it out."
    func extractWorkoutFromChat(userId: String, history: [KaiMessage]) async throws -> GeneratedWorkout? {
        guard let skill = SkillLoader.shared.skill(named: "extract_workout") else {
            throw WorkoutExtractionError.incompletePlan
        }

        // Only the last N turns matter here — this extracts the latest
        // agreed plan, not the full history a chat call would need for
        // tone/context. Rendered through the skill's own template (its
        // {{transcript}} placeholder) rather than left for
        // discoverAndRunSkill to fill, since with a single candidate skill
        // there's no ambiguity about which template governs the message —
        // that ambiguity is exactly what multi-skill call sites can't do
        // this rendering step for, which is why discoverAndRunSkill itself
        // sends the raw conversation rather than a pre-filled template.
        let transcript = history.suffix(20)
            .map { "\($0.role == .user ? "User" : "Kai"): \($0.content)" }
            .joined(separator: "\n")
        let prompt = skill.renderedPrompt(placeholders: ["transcript": transcript])

        let dispatch = try await discoverAndRunSkill(
            message: prompt,
            userId: userId,
            history: [],
            candidateSkills: [skill]
        )

        guard case .matched(_, let input) = dispatch else { return nil }
        guard input["found_plan"] as? Bool == true else { return nil }

        guard let data = try? JSONSerialization.data(withJSONObject: input) else {
            throw WorkoutExtractionError.incompletePlan
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let decoded = try? decoder.decode(GeneratedWorkout.self, from: data) else {
            throw WorkoutExtractionError.incompletePlan
        }

        let context = await contextBuilder.buildSnapshot(userId: userId)
        return GeneratedWorkout(
            id: decoded.id,
            name: decoded.name,
            workoutType: decoded.workoutType,
            estimatedDurationMins: decoded.estimatedDurationMins,
            coachingNote: decoded.coachingNote,
            exercises: decoded.exercises,
            contextSnapshot: context
        )
    }

    /// Kai's weekly read — the named premium differentiator for the
    /// Insights tab (roadmap Phase 3). Aggregates recent sessions into
    /// volume/recovery/Momentum (InsightsEngine, pure Swift, no model
    /// call) and hands that summary to the bundled weekly_insight skill to
    /// interpret in Kai's own voice. The first real consumer of the Phase 2
    /// skills framework: no bespoke ClaudeTool, no hand-written prompt file —
    /// just this method filling placeholders and calling run(skill:).
    func generateWeeklyInsight(userId: String) async throws -> String {
        guard let skill = SkillLoader.shared.skill(named: "weekly_insight") else {
            throw ClaudeAPIError.malformedResponse
        }

        // A wide lookback (not just the trailing 7 days) — recovery needs
        // to see further back than the volume window does to say anything
        // useful about a genuinely stale muscle group.
        let sessions = (try? await ForzeeDataService.shared.fetchSessionHistory(userId: userId, limit: 60)) ?? []

        let volume = InsightsEngine.weeklySetVolume(sessions: sessions)
        let recovery = InsightsEngine.daysSinceLastTrained(sessions: sessions)
        let momentum = InsightsEngine.momentumScore(sessions: sessions)

        let volumeSummary = MuscleGroup.allCases.map { group in
            "\(group.displayName): \(volume[group] ?? 0) of \(group.weeklySetTarget) target sets"
        }.joined(separator: "\n")

        let recoverySummary = MuscleGroup.allCases.map { group -> String in
            if let days = recovery[group] {
                return "\(group.displayName): \(days) day\(days == 1 ? "" : "s") ago"
            }
            return "\(group.displayName): no recent session data"
        }.joined(separator: "\n")

        let input = try await run(
            skill: skill,
            placeholders: [
                "volume_summary": volumeSummary,
                "recovery_summary": recoverySummary,
                "momentum_score": String(momentum),
            ],
            userId: userId
        )

        return input["insight"] as? String ?? "Kai couldn't put together this week's read — try again in a bit."
    }

    // MARK: - Skills Framework

    /// Runs exactly one named skill, forcing Claude to respond through its
    /// tool — the generic replacement for the old pattern of a bespoke
    /// KaiEngine method + hand-written ClaudeTool per capability. Use this
    /// when the caller already knows which skill applies and needs a
    /// guaranteed structured result (never plain prose) — e.g. a mid-workout
    /// voice command, which always needs *some* decision back. For "let
    /// Claude decide whether any of several skills fit," see
    /// `discoverAndRunSkill` instead.
    func run(skill: Skill, placeholders: [String: String], userId: String) async throws -> [String: Any] {
        let prompt = skill.renderedPrompt(placeholders: placeholders)

        let input = try await apiClient.completeWithTool(
            model: skill.model,
            systemPrompt: KaiSystemPrompt.identityOnly,
            userMessage: prompt,
            tool: skill.tool,
            maxTokens: 1024
        )

        // outputTokens: 0 — a generic runner has no per-skill way to know
        // which output field is the "real" reply text to size (interpretWorkoutVoiceCommand
        // used to size this off spoken_reply specifically). Usage records
        // are cost estimates already, not billed truth, so this undercounts
        // output cost slightly for skills with a substantial text field —
        // an accepted trade-off for not hand-writing that per skill.
        await usageGate.recordUsage(
            userId: userId,
            taskType: skill.name,
            model: skill.model,
            inputTokens: prompt.estimatedTokenCount,
            outputTokens: 0
        )

        return input
    }

    /// Model-layer skill discovery: hands Claude every candidate skill as an
    /// available tool in one call (`tool_choice: auto`) and lets it decide
    /// whether one applies — no classifier guessing intent first, and no
    /// enum case anywhere naming which skills exist. Defaults to every
    /// bundled skill; pass `candidateSkills` to narrow the set for a call
    /// site that only makes sense offering one or a few (e.g. a dedicated
    /// button already declaring its own intent).
    func discoverAndRunSkill(
        message: String,
        userId: String,
        history: [KaiMessage],
        candidateSkills: [Skill]? = nil,
        model: KaiModel = .haiku,
        systemPrompt: String = KaiSystemPrompt.identityOnly
    ) async throws -> SkillDispatchResult {
        let skills = candidateSkills ?? SkillLoader.shared.skills
        let messages = Array(history.suffix(20)) + [KaiMessage(role: .user, content: message)]

        // The model that decides *and* executes in the same call — deciding
        // which skill (if any) applies isn't a separate round trip from
        // producing that skill's structured output, so this is the model
        // both run on. Defaults to Haiku (fast/cheap intent routing); pass
        // `model:` when the candidate set needs Sonnet's judgment to
        // discriminate well.
        let result = try await apiClient.completeWithTools(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            tools: skills.map(\.tool)
        )

        switch result {
        case .text(let text):
            return .noSkillMatched(text: text)
        case .toolUse(let skillName, let input):
            guard let skill = skills.first(where: { $0.name == skillName }) else {
                return .noSkillMatched(text: "")
            }
            await usageGate.recordUsage(
                userId: userId,
                taskType: skill.name,
                model: skill.model,
                inputTokens: message.estimatedTokenCount,
                outputTokens: 0
            )
            return .matched(skill: skill, input: input)
        }
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

// MARK: - SkillDispatchResult

/// The outcome of `discoverAndRunSkill` — Claude either picked one of the
/// candidate skills (with its structured input) or decided none applied,
/// in which case `text` is whatever plain reply it gave instead.
enum SkillDispatchResult {
    case matched(skill: Skill, input: [String: Any])
    case noSkillMatched(text: String)
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
