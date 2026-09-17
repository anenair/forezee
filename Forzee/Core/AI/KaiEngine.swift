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
    /// No skill routing — always a normal streamed reply. Used by callers
    /// that want a plain answer regardless of what's bundled (WorkoutTabView's
    /// mid-workout voice escalation, where a plan change mid-set would be a
    /// strange thing to trigger by accident).
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
        try await usageGate.checkLimit(userId: userId, taskType: .chatMessage)
        let context = await contextBuilder.buildSnapshot(userId: userId)

        isResponding = true
        defer { isResponding = false }

        try await performChatCompletion(
            message: message, userId: userId, history: history, context: context,
            onToken: onToken, onComplete: onComplete
        )
    }

    /// The plain streamed-text completion path — used by chat() (mid-workout
    /// voice escalation, gym companion, etc.), which never needs the
    /// structured CoachResponse protocol. Coach chat's own text uses
    /// sendCoachMessage's forced-tool path instead; see that method.
    private func performChatCompletion(
        message: String,
        userId: String,
        history: [KaiMessage],
        context: UserContextSnapshot,
        onToken: @escaping (String) -> Void,
        onComplete: @escaping (KaiMessage) -> Void
    ) async throws {
        let model = taskClassifier.classify(message: message, context: context)
        let messages = assembleMessages(userMessage: message, history: history, context: context)

        // Persist the user's message now, not after the reply — best-effort,
        // matches the rest of the app's policy of treating chat history as
        // lower-stakes (see SyncManager). Never blocks or fails the chat turn.
        try? await ForzeeDataService.shared.saveMessage(KaiMessage(role: .user, content: message), userId: userId)

        let fullResponse = try await apiClient.streamCompletion(
            model: model,
            systemPrompt: .layered(KaiSystemPrompt.buildLayered(context: context)),
            messages: messages,
            taskType: KaiTaskType.chatMessage.rawValue,
            onToken: onToken
        )

        await usageGate.recordUsage(
            userId: userId,
            taskType: .chatMessage,
            model: model,
            inputTokens: messages.estimatedTokenCount,
            outputTokens: fullResponse.estimatedTokenCount
        )

        let responseMessage = KaiMessage(role: .assistant, content: fullResponse)
        try? await ForzeeDataService.shared.saveMessage(responseMessage, userId: userId)
        onComplete(responseMessage)
    }

    /// The Coach tab's structured reply path (see Core/AI/CoachProtocol) —
    /// every turn comes back as a CoachResponse. One call hands Claude
    /// both the main send_coach_response tool AND the candidate skills
    /// (adjust_plan_from_chat/recovery_check/show_progress) with
    /// `tool_choice: auto`, so Claude itself decides which one applies —
    /// no separate "does a skill match?" round trip before the real
    /// reply even starts. (An earlier version ran skill discovery as its
    /// own Haiku call first; that meant every message paid for a second
    /// network round trip, plus a discarded prose answer on the common
    /// case where nothing matched.)
    ///
    /// Runs schema validation (the Codable decode inside
    /// CoachResponse.from(toolInput:)) and then domain validation
    /// (CoachResponseValidator.sanitize) before ever returning a
    /// send_coach_response result — a response that fails either becomes
    /// a graceful fallback text reply, never a crash or a nonsensical
    /// block reaching the UI.
    ///
    /// `onPartialText` gets a live-typable preview WHILE the reply is
    /// still generating: plain text streams directly, and a
    /// send_coach_response tool call gets its first text/coaching_note
    /// block previewed via IncrementalCoachTextExtractor (see
    /// ClaudeAPIClient.streamCompletionWithTools) — a matched skill's
    /// short JSON payload isn't previewed, it just resolves in one shot.
    func sendCoachMessage(
        message: String,
        userId: String,
        history: [KaiMessage],
        onPartialText: @escaping (String) -> Void = { _ in }
    ) async throws -> CoachResponse {
        try await usageGate.checkLimit(userId: userId, taskType: .chatMessage)
        let context = await contextBuilder.buildSnapshot(userId: userId)

        isResponding = true
        defer { isResponding = false }

        try? await ForzeeDataService.shared.saveMessage(KaiMessage(role: .user, content: message), userId: userId)

        let candidateSkills = ["adjust_plan_from_chat", "recovery_check", "show_progress"].compactMap(SkillLoader.shared.skill(named:))
        let model = taskClassifier.classify(message: message, context: context)
        let messages = assembleMessages(userMessage: message, history: history, context: context)
        let tools = candidateSkills.map(\.tool) + [CoachResponse.tool]

        var response: CoachResponse
        var matchedSkillForUsage: Skill?
        do {
            let result = try await apiClient.streamCompletionWithTools(
                model: model,
                systemPrompt: .layered(KaiSystemPrompt.buildLayered(context: context)),
                messages: messages,
                tools: tools,
                previewToolName: CoachResponse.tool.name,
                taskType: KaiTaskType.chatMessage.rawValue,
                onPartialText: onPartialText
            )

            switch result {
            case .toolUse(let name, let input) where name == CoachResponse.tool.name:
                let decoded = try CoachResponse.from(toolInput: input)
                response = CoachResponseValidator.sanitize(decoded)

            case .toolUse(let name, let input):
                if let skill = candidateSkills.first(where: { $0.name == name }) {
                    matchedSkillForUsage = skill
                    if skill.name == "show_progress" {
                        // Haiku/Sonnet only identified WHICH exercise — the
                        // numbers below come straight from real logged sets
                        // (InsightsEngine), never from the model, matching
                        // the system prompt's "never fabricate health data"
                        // rule.
                        response = await buildProgressResponse(exerciseName: input["exercise_name"] as? String, userId: userId)
                    } else {
                        let replyText = handleChatSkillReply(skill, input: input)
                        if skill.name == "adjust_plan_from_chat" {
                            try? await applyPlanAdjustment(input, userId: userId)
                        }
                        response = CoachResponse(blocks: [.text(TextBlock(content: replyText))])
                    }
                } else {
                    response = CoachResponse(blocks: [.text(TextBlock(
                        content: "Something in Kai's skills got confused — try again."
                    ))])
                }

            case .text(let text):
                // Claude chose not to call any tool — still not an error,
                // just wrap it exactly like an old pre-protocol message
                // (see CoachResponse.parse(legacyContent:)).
                response = CoachResponse(blocks: [.text(TextBlock(content: text))])
            }
        } catch {
            // Schema validation (decode) or the network call itself
            // failed — never surface that as a broken chat bubble.
            response = CoachResponse(blocks: [.text(TextBlock(
                content: "I had trouble putting that together — try asking again."
            ))])
        }

        if let skill = matchedSkillForUsage {
            await usageGate.recordUsage(
                userId: userId, taskType: skill.name, model: model,
                inputTokens: messages.estimatedTokenCount, outputTokens: 0
            )
        } else {
            await usageGate.recordUsage(
                userId: userId, taskType: .chatMessage, model: model,
                inputTokens: messages.estimatedTokenCount,
                outputTokens: response.plainTextSummary.estimatedTokenCount
            )
        }

        try? await ForzeeDataService.shared.saveMessage(
            KaiMessage(role: .assistant, content: response.encodedContent()), userId: userId
        )
        return response
    }

    // MARK: - Chat Skill Handling

    private func handleChatSkillReply(_ skill: Skill, input: [String: Any]) -> String {
        switch skill.name {
        case "adjust_plan_from_chat":
            return input["confirmation_reply"] as? String ?? "Done."
        case "recovery_check":
            return input["reply"] as? String ?? "I couldn't put together a recommendation — try again."
        default:
            return "Something in Kai's skills got confused — try again."
        }
    }

    /// Builds a real ProgressBlock from InsightsEngine.exerciseProgress —
    /// the show_progress skill only ever tells us WHICH exercise; every
    /// number here is read straight off actual logged sets. Falls back to
    /// a plain text reply (never a ProgressBlock with made-up numbers)
    /// when there's no exercise name or no matching history.
    private func buildProgressResponse(exerciseName: String?, userId: String) async -> CoachResponse {
        guard let exerciseName, !exerciseName.trimmingCharacters(in: .whitespaces).isEmpty else {
            return CoachResponse(blocks: [.text(TextBlock(
                content: "Which exercise did you want to check progress on?"
            ))])
        }

        let sessions = (try? await ForzeeDataService.shared.fetchSessionHistory(userId: userId, limit: 60)) ?? []
        guard let progress = InsightsEngine.exerciseProgress(sessions: sessions, exerciseName: exerciseName) else {
            return CoachResponse(blocks: [.text(TextBlock(
                content: "I don't have any logged sets for \(exerciseName) yet — log a session with it and ask again."
            ))])
        }

        let block = ProgressBlock(
            title: "\(exerciseName.capitalized) Progress",
            metric: "top_set_weight_kg",
            current: progress.current,
            previous: progress.previous,
            unit: "kg"
        )
        return CoachResponse(blocks: [.progress(block)])
    }

    /// Applies only the fields the model actually included — see
    /// adjust_plan_from_chat's own instruction to omit anything not being
    /// changed. Updates both the persisted profile and AppState's in-memory
    /// copy so My Plan (and every other screen reading appState.userProfile)
    /// reflects the change immediately, not just on next app launch.
    private func applyPlanAdjustment(_ input: [String: Any], userId: String) async throws {
        var updates: [String: Any] = [:]
        for key in [
            "training_split", "exercise_variability", "warmup_sets_enabled",
            "circuits_supersets_enabled", "weight_unit", "start_of_week",
            "preferred_duration_mins", "coach_mode", "fitness_level",
        ] {
            if let value = input[key] {
                updates[key] = value
            }
        }
        guard !updates.isEmpty else { return }

        try await ForzeeDataService.shared.updateProfile(updates, userId: userId)

        guard let profile = AppState.shared?.userProfile else { return }
        var updated = profile
        if let v = updates["training_split"] as? String { updated.trainingSplit = v }
        if let v = updates["exercise_variability"] as? String { updated.exerciseVariability = v }
        if let v = updates["warmup_sets_enabled"] as? Bool { updated.warmupSetsEnabled = v }
        if let v = updates["circuits_supersets_enabled"] as? Bool { updated.circuitsSupersetsEnabled = v }
        if let v = updates["weight_unit"] as? String { updated.weightUnit = v }
        if let v = updates["start_of_week"] as? String { updated.startOfWeek = v }
        if let v = Self.intValue(updates["preferred_duration_mins"]) { updated.preferredDurationMins = v }
        if let v = updates["coach_mode"] as? String { updated.coachMode = v }
        if let v = updates["fitness_level"] as? String { updated.fitnessLevel = v }
        AppState.shared?.userProfile = updated
    }

    /// JSONSerialization boxes JSON numbers as NSNumber, and a bare `as? Int`
    /// on that isn't reliable (same reasoning as WorkoutVoiceCommandResult's
    /// own intValue helper) — this covers Int, Double, and NSNumber alike.
    private static func intValue(_ any: Any?) -> Int? {
        if let i = any as? Int { return i }
        if let d = any as? Double { return Int(d) }
        if let n = any as? NSNumber { return n.intValue }
        return nil
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
            systemPrompt: .layered(KaiSystemPrompt.buildLayered(context: context)),
            userMessage: prompt,
            taskType: KaiTaskType.workoutGeneration.rawValue
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
            systemPrompt: .layered(KaiSystemPrompt.buildLayered(context: context)),
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
            systemPrompt: .plain(KaiSystemPrompt.identityOnly),
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

        let summaries = await buildInsightSummaries(userId: userId)
        let input = try await run(
            skill: skill,
            placeholders: [
                "volume_summary": summaries.volume,
                "recovery_summary": summaries.recovery,
                "momentum_score": String(summaries.momentum),
            ],
            userId: userId
        )

        return input["insight"] as? String ?? "Kai couldn't put together this week's read — try again in a bit."
    }

    /// On-demand version of the weekly read — "why did my momentum drop?" —
    /// answering one specific question against the same InsightsEngine
    /// numbers instead of a scheduled summary. Forced via run(skill:), not
    /// chat discovery: the data it needs (a session-history fetch +
    /// aggregation) is deliberately kept out of every chat message's cheap
    /// context snapshot, so this only runs when the user is already looking
    /// at the Insights tab and asks something.
    func explainInsight(question: String, userId: String) async throws -> String {
        guard let skill = SkillLoader.shared.skill(named: "explain_insight") else {
            throw ClaudeAPIError.malformedResponse
        }

        let summaries = await buildInsightSummaries(userId: userId)
        let input = try await run(
            skill: skill,
            placeholders: [
                "question": question,
                "volume_summary": summaries.volume,
                "recovery_summary": summaries.recovery,
                "momentum_score": String(summaries.momentum),
            ],
            userId: userId
        )

        return input["reply"] as? String ?? "Kai couldn't answer that — try again in a bit."
    }

    /// Shared by generateWeeklyInsight and explainInsight — same aggregation,
    /// same wide (60-session) lookback since Recovery needs to see further
    /// back than the volume window does to say anything useful about a
    /// genuinely stale muscle group.
    private func buildInsightSummaries(userId: String) async -> (volume: String, recovery: String, momentum: Int) {
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

        return (volumeSummary, recoverySummary, momentum)
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
            systemPrompt: .plain(KaiSystemPrompt.identityOnly),
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
        systemPrompt: SystemPrompt = .plain(KaiSystemPrompt.identityOnly)
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
            systemPrompt: .layered(KaiSystemPrompt.buildLayered(context: context)),
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
        let recentHistory = Array(history.suffix(5)).map(Self.conversationalCopy)
        return recentHistory + [KaiMessage(role: .user, content: userMessage)]
    }

    /// An assistant turn's stored `content` is the full encoded CoachResponse
    /// protocol JSON (see CoachView's `messages.append(reply)`) — the UI
    /// needs that verbatim to re-render blocks/actions on screen, but it's
    /// never what should go back to Claude as its OWN prior turn: sending
    /// raw protocol JSON as conversation history shows the model a garbled
    /// version of what it "said" instead of what a person actually saw,
    /// and the pollution compounds with every additional turn in a
    /// conversation — the likely cause of replies getting more fragile
    /// (and eventually failing to parse) the longer a chat runs. Swaps an
    /// assistant message's content for its plain-language summary before
    /// it's ever sent as history; a user message, or an old plain-text
    /// message from before this protocol existed, passes through
    /// unchanged (CoachResponse.parse(legacyContent:)'s fallback already
    /// makes a single TextBlock's plainTextSummary equal to the original text).
    private static func conversationalCopy(_ message: KaiMessage) -> KaiMessage {
        guard message.role == .assistant else { return message }
        let summary = CoachResponse.parse(legacyContent: message.content).plainTextSummary
        guard !summary.isEmpty else { return message }
        return KaiMessage(id: message.id, role: message.role, content: summary, createdAt: message.createdAt)
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
