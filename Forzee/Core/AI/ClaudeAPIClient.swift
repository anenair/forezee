// ============================================================
// ClaudeAPIClient.swift
// Forzee — Core/AI
//
// Low-level HTTP client for the Anthropic Claude Messages API.
// Handles both streaming and non-streaming completions.
//
// All higher-level logic (model routing, context building,
// usage gating) lives in KaiEngine — this file is transport only.
// ============================================================

import Foundation

// MARK: - SystemPrompt

/// A system prompt as one or more cache-aware text blocks. Anthropic's
/// prompt cache is a byte-prefix match over `tools` -> `system` ->
/// `messages`, in that render order — a `cache_control` marker on the LAST
/// block of `system` also covers every tool definition before it, so tools
/// never need their own marker as long as the tool list stays deterministic
/// per call site.
struct SystemPrompt {
    enum CacheControl {
        case none
        case ephemeral         // default 5-minute TTL
        case ephemeralOneHour  // explicit 1-hour TTL — worth the 2x write premium only when reused often enough to pay it back (see shared/prompt-caching.md)

        var jsonValue: [String: Any]? {
            switch self {
            case .none: return nil
            case .ephemeral: return ["type": "ephemeral"]
            case .ephemeralOneHour: return ["type": "ephemeral", "ttl": "1h"]
            }
        }
    }

    struct Block {
        let text: String
        let cache: CacheControl
    }

    let blocks: [Block]

    /// A single block, no caching — for prompts too small or too one-off to
    /// bother (e.g. the identity-only gym companion comment).
    static func plain(_ text: String) -> SystemPrompt {
        SystemPrompt(blocks: [Block(text: text, cache: .none)])
    }

    /// The three-layer shape every Kai call with a context snapshot uses:
    /// global static text (identical for every user, cached for an hour),
    /// per-user text (changes only in Settings, cached for 5 minutes), then
    /// the live context last, never cached. See KaiSystemPrompt.buildLayered.
    static func layered(_ prompt: KaiSystemPrompt.LayeredSystemPrompt) -> SystemPrompt {
        SystemPrompt(blocks: [
            Block(text: prompt.global, cache: .ephemeralOneHour),
            Block(text: prompt.perUser, cache: .ephemeral),
            Block(text: prompt.volatile, cache: .none),
        ])
    }

    /// The exact JSON value for the request body's `system` field.
    var jsonValue: [[String: Any]] {
        blocks.map { block in
            var dict: [String: Any] = ["type": "text", "text": block.text]
            if let cache = block.cache.jsonValue { dict["cache_control"] = cache }
            return dict
        }
    }
}

// MARK: - Per-model request rules

extension KaiModel {
    /// Thinking/effort fields each model needs. Sonnet 5 runs adaptive
    /// thinking when `thinking` is omitted (Sonnet 4.6 didn't), so it's
    /// disabled explicitly to keep Coach chat's latency and cost where they
    /// were — and forced tool_choice working for Sonnet-routed skills.
    /// Opus 5.5 rejects `thinking: disabled` outright (always-on adaptive
    /// thinking); effort is its only control, pinned per model because
    /// changing it between requests invalidates the prompt cache.
    var reasoningFields: [String: Any] {
        switch self {
        case .sonnet: return ["thinking": ["type": "disabled"]]
        case .opus:   return ["output_config": ["effort": "medium"]]
        }
    }

    /// Opus 5.5 rejects `tool_choice` `tool`/`any` with a 400, so it gets
    /// `auto` plus an explicit prompt instruction (`forcedToolInstruction`).
    func toolChoice(forcing toolName: String) -> [String: Any] {
        self == .opus ? ["type": "auto"] : ["type": "tool", "name": toolName]
    }

    /// nil for models that still accept a forced tool_choice.
    func forcedToolInstruction(_ toolName: String) -> String? {
        self == .opus ? "Respond only by calling the \(toolName) tool." : nil
    }

    /// On Opus 5.5 `max_tokens` covers thinking plus the reply, so a limit
    /// sized for reply text alone would cut structured output off mid-JSON.
    func maxTokens(_ requested: Int) -> Int {
        self == .opus ? max(requested, 16_000) : requested
    }
}

final class ClaudeAPIClient {

    // MARK: - Configuration

    private let urlSession: URLSession

    init() {
        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    /// Every call goes through the claude-chat Edge Function
    /// (supabase/functions/claude-chat), which holds the Anthropic key
    /// server-side and re-checks the free-tier limit against the caller's
    /// verified session. The key never ships inside the app.
    private func makeRequest() async throws -> URLRequest {
        try await ForzeeDataService.shared.edgeFunctionRequest("claude-chat")
    }

    // MARK: - Streaming Completion

    /// Stream a response token-by-token from the Claude Messages API.
    /// Returns the full assembled response string when the stream ends.
    func streamCompletion(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        taskType: String = "unspecified",
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        let request = try await buildRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            stream: true,
            taskType: taskType
        )

        var fullResponse = ""

        let (asyncBytes, response) = try await urlSession.bytes(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }

            #if DEBUG
            Self.logCacheUsageIfMessageStart(json)
            #endif

            if let token = parseStreamToken(json) {
                fullResponse += token
                await MainActor.run { onToken(token) }
            }
        }

        return fullResponse
    }

    // MARK: - Non-Streaming Completion

    /// Request a full, non-streamed completion. Use for structured outputs (e.g. workout JSON).
    func complete(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        userMessage: String,
        taskType: String = "unspecified"
    ) async throws -> String {
        let messages = [KaiMessage(role: .user, content: userMessage)]
        let request = try await buildRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            stream: false,
            taskType: taskType
        )

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        #if DEBUG
        Self.logCacheUsage(from: data)
        #endif

        return try parseNonStreamResponse(data)
    }

    // MARK: - Tool Use (structured output)

    /// Forces Claude to respond via a single named tool, guaranteeing a
    /// structured (JSON) result instead of free-form prose — used for real
    /// LLM understanding of mid-workout voice commands (intent + extracted
    /// weight/reps) without falling back to hand-rolled pattern matching.
    func completeWithTool(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        userMessage: String,
        tool: ClaudeTool,
        maxTokens: Int = 300,
        taskType: String = "unspecified"
    ) async throws -> [String: Any] {
        var request = try await makeRequest()

        let content = model.forcedToolInstruction(tool.name).map { "\(userMessage)\n\n\($0)" } ?? userMessage
        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(maxTokens),
            "system": systemPrompt.jsonValue,
            "messages": [["role": "user", "content": content]],
            "tools": [[
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            ]],
            "tool_choice": model.toolChoice(forcing: tool.name),
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        #if DEBUG
        Self.logCacheUsage(from: data)
        #endif

        return try parseToolUseResponse(data, toolName: tool.name)
    }

    /// Forces a single named tool while still sending full conversation
    /// history and system prompt — completeWithTool's flattened
    /// single-message form can't carry multi-turn context; completeWithTools
    /// carries context but leaves the choice to Claude (tool_choice: auto).
    /// This is the "always structured, but with real conversation context"
    /// combination the main Coach chat reply needs (see
    /// KaiEngine.sendCoachMessage / CoachResponse.tool).
    func completeWithForcedTool(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        tool: ClaudeTool,
        maxTokens: Int = 1536,
        taskType: String = "unspecified"
    ) async throws -> [String: Any] {
        var request = try await makeRequest()

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(maxTokens),
            "system": systemPrompt.jsonValue,
            "messages": Self.messagesJSON(messages, appending: model.forcedToolInstruction(tool.name)),
            "tools": [["name": tool.name, "description": tool.description, "input_schema": tool.inputSchema]],
            "tool_choice": model.toolChoice(forcing: tool.name),
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        #if DEBUG
        Self.logCacheUsage(from: data)
        #endif

        return try parseToolUseResponse(data, toolName: tool.name)
    }

    /// Same as completeWithForcedTool, but streamed — Claude's Messages
    /// API streams a forced tool call's JSON arguments incrementally too,
    /// exactly the same SSE mechanism as plain text (`streamCompletion`
    /// above): a series of `content_block_delta` events, just carrying
    /// `input_json_delta`/`partial_json` fragments instead of
    /// `text_delta`/`text`. `onPartialJSON` gets the full accumulated (but
    /// not-yet-valid) JSON text after every fragment — see
    /// IncrementalCoachTextExtractor for how a caller turns that into
    /// something actually displayable before the object is complete.
    ///
    /// Requires `eager_input_streaming: true` on the tool definition —
    /// without it, Anthropic's API buffers a tool call's arguments and
    /// sends them as one chunk near the end of the stream regardless of
    /// `stream: true`, which is indistinguishable from "not streaming" on
    /// the receiving end (this was a real, confirmed bug: no beta header
    /// exists for this, it's a plain field on the tool). Because eager
    /// streaming skips the API's own input validation, an accumulated
    /// buffer that hits `maxTokens` before the object closes can be
    /// incomplete/invalid JSON — the caller (KaiEngine.sendCoachMessage)
    /// already treats a JSONSerialization failure as a graceful fallback,
    /// not a crash, which is exactly the guard this needs.
    func streamCompletionWithForcedTool(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        tool: ClaudeTool,
        maxTokens: Int = 8192,
        taskType: String = "unspecified",
        onPartialJSON: @escaping (String) -> Void
    ) async throws -> [String: Any] {
        var request = try await makeRequest()

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(maxTokens),
            "stream": true,
            "system": systemPrompt.jsonValue,
            "messages": Self.messagesJSON(messages, appending: model.forcedToolInstruction(tool.name)),
            "tools": [[
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
                "eager_input_streaming": true,
            ]],
            "tool_choice": model.toolChoice(forcing: tool.name),
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        var accumulatedJSON = ""
        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }

            #if DEBUG
            Self.logCacheUsageIfMessageStart(json)
            #endif

            if let fragment = parseInputJSONDelta(json) {
                accumulatedJSON += fragment
                await MainActor.run { onPartialJSON(accumulatedJSON) }
            }
        }

        guard let data = accumulatedJSON.data(using: .utf8),
              let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ClaudeAPIError.malformedResponse
        }
        return input
    }

    /// Same idea as `streamCompletionWithForcedTool`, but `tool_choice: auto`
    /// over several tools at once — Claude picks whichever one applies (or
    /// none, replying in plain text) in a single round trip, instead of a
    /// caller running a separate "does any of these apply?" call first and
    /// only then making this one. Every tool gets `eager_input_streaming`
    /// so a tool-use pick still streams incrementally, exactly like
    /// `streamCompletionWithForcedTool`; `previewToolName` names which one
    /// of the given tools' input should get a live text preview via
    /// `IncrementalCoachTextExtractor` while it's still generating (the
    /// others resolve in one shot when they close — they're short enough
    /// that there's nothing worth previewing).
    func streamCompletionWithTools(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        tools: [ClaudeTool],
        previewToolName: String,
        maxTokens: Int = 8192,
        taskType: String = "unspecified",
        onPartialText: @escaping (String) -> Void
    ) async throws -> StreamedAutoToolResult {
        var request = try await makeRequest()

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(maxTokens),
            "stream": true,
            "system": systemPrompt.jsonValue,
            "messages": Self.messagesJSON(messages),
            "tools": tools.map {
                ["name": $0.name, "description": $0.description, "input_schema": $0.inputSchema, "eager_input_streaming": true]
            },
            "tool_choice": ["type": "auto"],
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (asyncBytes, response) = try await urlSession.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        // Anthropic's stream can carry more than one content block (e.g. a
        // tool_use alongside stray prose), each identified by its own
        // `index` in content_block_start/delta events — this tracks all of
        // them rather than assuming there's exactly one, the same way
        // parseToolChoiceResponse does for the non-streaming multi-tool path.
        var blockOrder: [Int] = []
        var blockKinds: [Int: String] = [:]
        var blockToolNames: [Int: String] = [:]
        var blockBuffers: [Int: String] = [:]

        for try await line in asyncBytes.lines {
            guard line.hasPrefix("data: ") else { continue }
            let json = String(line.dropFirst(6))
            guard json != "[DONE]" else { break }
            guard let data = json.data(using: .utf8),
                  let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let type = obj["type"] as? String else { continue }

            switch type {
            #if DEBUG
            case "message_start":
                if let message = obj["message"] as? [String: Any] {
                    Self.logCacheUsage(message["usage"] as? [String: Any])
                }
            #endif

            case "content_block_start":
                guard let index = obj["index"] as? Int,
                      let block = obj["content_block"] as? [String: Any],
                      let blockType = block["type"] as? String else { continue }
                blockOrder.append(index)
                blockKinds[index] = blockType
                blockBuffers[index] = ""
                if blockType == "tool_use", let name = block["name"] as? String {
                    blockToolNames[index] = name
                }

            case "content_block_delta":
                guard let index = obj["index"] as? Int,
                      let delta = obj["delta"] as? [String: Any],
                      let deltaType = delta["type"] as? String else { continue }
                if deltaType == "text_delta", let text = delta["text"] as? String {
                    // Accumulated for the final `.text` fallback below, but
                    // deliberately NOT previewed live: with tool_choice
                    // "auto", Claude can emit this as stray prose ahead of
                    // a forced-schema tool_use block that arrives after it
                    // and wins (see the tool-call-wins comment below) — a
                    // live preview of this text would show, then get
                    // silently swapped out for the tool's own content once
                    // that block starts streaming. Confirmed in practice:
                    // a reply that visibly started with one line and then
                    // "flipped" to a different, contradicting one.
                    blockBuffers[index, default: ""] += text
                } else if deltaType == "input_json_delta", let fragment = delta["partial_json"] as? String {
                    blockBuffers[index, default: ""] += fragment
                    if blockToolNames[index] == previewToolName,
                       let preview = IncrementalCoachTextExtractor.preview(fromRawJSON: blockBuffers[index] ?? "") {
                        await MainActor.run { onPartialText(preview) }
                    }
                }

            default:
                continue
            }
        }

        // A tool call wins over any accompanying prose — same rule as
        // parseToolChoiceResponse. First one in generation order, in the
        // rare case Claude emits more than one.
        for index in blockOrder where blockKinds[index] == "tool_use" {
            guard let name = blockToolNames[index] else { continue }
            let jsonText = blockBuffers[index] ?? ""
            guard let data = jsonText.data(using: .utf8),
                  let input = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                // The buffer never closed into valid JSON — almost always
                // because the stream ended (maxTokens, a dropped
                // connection) before the tool call's object finished. The
                // live preview above already revealed this reply's opening
                // line character-by-character from the very same buffer,
                // scanning for it regardless of whether the JSON around it
                // ever closes — so salvage that same text as a plain reply
                // instead of discarding it and surfacing a bare failure
                // that overwrites a message the user already watched
                // appear on screen.
                if name == previewToolName,
                   let salvaged = IncrementalCoachTextExtractor.preview(fromRawJSON: jsonText),
                   !salvaged.isEmpty {
                    return .text(salvaged)
                }
                throw ClaudeAPIError.malformedResponse
            }
            return .toolUse(name: name, input: input)
        }

        let text = blockOrder
            .filter { blockKinds[$0] == "text" }
            .compactMap { blockBuffers[$0] }
            .joined()
        return .text(text)
    }

    private func parseInputJSONDelta(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "content_block_delta",
              let delta = obj["delta"] as? [String: Any],
              let deltaType = delta["type"] as? String,
              deltaType == "input_json_delta",
              let partialJSON = delta["partial_json"] as? String else {
            return nil
        }
        return partialJSON
    }

    // MARK: - Tool Use (model-driven skill discovery)

    /// Hands Claude every candidate tool at once with `tool_choice: auto`
    /// and lets the model itself decide whether any applies — the
    /// model-layer half of skill discovery (SkillLoader handles the other
    /// half: turning bundled .md files into Swift tool schemas with no
    /// registration step). Unlike `completeWithTool`, Claude is free to
    /// reply with plain text instead of calling a tool — that's not a
    /// failure, it means none of the candidates fit this message.
    func completeWithTools(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        tools: [ClaudeTool],
        maxTokens: Int = 1024,
        taskType: String = "unspecified"
    ) async throws -> ClaudeToolChoiceResult {
        guard !tools.isEmpty else {
            // No skills loaded — same shape as "Claude chose not to use a tool."
            let text = try await complete(
                model: model,
                systemPrompt: systemPrompt,
                userMessage: messages.last?.content ?? "",
                taskType: taskType
            )
            return .text(text)
        }

        var request = try await makeRequest()

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(maxTokens),
            "system": systemPrompt.jsonValue,
            "messages": Self.messagesJSON(messages),
            "tools": tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.inputSchema] },
            "tool_choice": ["type": "auto"],
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        #if DEBUG
        Self.logCacheUsage(from: data)
        #endif

        return try parseToolChoiceResponse(data)
    }

    private func parseToolChoiceResponse(_ data: Data) throws -> ClaudeToolChoiceResult {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw ClaudeAPIError.malformedResponse
        }

        // Claude can emit prose alongside a tool call, purely a tool call, or
        // purely prose. Any tool_use block means Claude picked a skill;
        // otherwise fall back to whatever text it assembled.
        if let toolBlock = content.first(where: { ($0["type"] as? String) == "tool_use" }),
           let name = toolBlock["name"] as? String,
           let input = toolBlock["input"] as? [String: Any] {
            return .toolUse(skillName: name, input: input)
        }

        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        return .text(text)
    }

    private func parseToolUseResponse(_ data: Data, toolName: String) throws -> [String: Any] {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let toolBlock = content.first(where: {
                  ($0["type"] as? String) == "tool_use" && ($0["name"] as? String) == toolName
              }),
              let input = toolBlock["input"] as? [String: Any] else {
            throw ClaudeAPIError.malformedResponse
        }
        return input
    }

    // MARK: - Private

    /// `instruction` is appended to the last message — how a model that
    /// can't be forced onto a tool (see KaiModel.forcedToolInstruction) is
    /// told to use one anyway.
    private static func messagesJSON(_ messages: [KaiMessage], appending instruction: String? = nil) -> [[String: Any]] {
        var json: [[String: Any]] = messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        if let instruction, let last = json.indices.last {
            json[last]["content"] = "\(json[last]["content"] as? String ?? "")\n\n\(instruction)"
        }
        return json
    }

    private func buildRequest(
        model: KaiModel,
        systemPrompt: SystemPrompt,
        messages: [KaiMessage],
        stream: Bool,
        taskType: String
    ) async throws -> URLRequest {
        var request = try await makeRequest()

        var body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": model.maxTokens(1024),
            "stream": stream,
            "system": systemPrompt.jsonValue,
            "messages": Self.messagesJSON(messages),
            "task_type": taskType,
        ]
        body.merge(model.reasoningFields) { _, new in new }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    #if DEBUG
    /// Verifies caching is actually working rather than assuming it from
    /// code review — cache_read_input_tokens should dominate on any repeat
    /// call that shares a cached prefix. Never trust the request shape
    /// alone; a later change to prompt assembly can silently break caching
    /// while everything keeps working, just at full price.
    private static func logCacheUsage(_ usage: [String: Any]?) {
        guard let usage else { return }
        let read = usage["cache_read_input_tokens"] as? Int ?? 0
        let write = usage["cache_creation_input_tokens"] as? Int ?? 0
        let input = usage["input_tokens"] as? Int ?? 0
        print("🗄️ Claude cache — read: \(read), write: \(write), uncached input: \(input)")
    }

    /// Non-streaming call sites: pull `usage` straight off the full response body.
    private static func logCacheUsage(from data: Data) {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        logCacheUsage(obj["usage"] as? [String: Any])
    }

    /// Streaming call sites: cache read/write is decided during input
    /// processing, before any output token generates, so `message_start`
    /// already carries the real cache numbers — no need to wait for the
    /// stream to finish.
    private static func logCacheUsageIfMessageStart(_ json: String) {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              obj["type"] as? String == "message_start",
              let message = obj["message"] as? [String: Any] else { return }
        logCacheUsage(message["usage"] as? [String: Any])
    }
    #endif

    private func parseStreamToken(_ json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let type = obj["type"] as? String,
              type == "content_block_delta",
              let delta = obj["delta"] as? [String: Any],
              let text = delta["text"] as? String else {
            return nil
        }
        return text
    }

    /// Selects text blocks by type rather than taking the first block — on
    /// Opus 5.5 every response leads with a `thinking` block, which has no
    /// `text` field.
    private func parseNonStreamResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]] else {
            throw ClaudeAPIError.malformedResponse
        }
        let text = content
            .filter { ($0["type"] as? String) == "text" }
            .compactMap { $0["text"] as? String }
            .joined()
        guard !text.isEmpty else { throw ClaudeAPIError.malformedResponse }
        return text
    }

    private func validateStatusCode(_ code: Int) throws {
        switch code {
        case 200...299: return
        case 401: throw ClaudeAPIError.unauthorized
        case 429: throw ClaudeAPIError.rateLimited
        case 500...599: throw ClaudeAPIError.serverError(statusCode: code)
        default: throw ClaudeAPIError.httpError(statusCode: code)
        }
    }
}

// MARK: - ClaudeTool

/// A single tool definition for Claude's tool-use API — see `completeWithTool`.
struct ClaudeTool {
    let name: String
    let description: String
    /// JSON Schema object (the Anthropic API's `input_schema`).
    let inputSchema: [String: Any]
}

// MARK: - ClaudeToolChoiceResult

/// The outcome of a `completeWithTools` call — Claude either picked one of
/// the candidate tools, or replied in plain text because none applied.
enum ClaudeToolChoiceResult {
    case toolUse(skillName: String, input: [String: Any])
    case text(String)
}

// MARK: - StreamedAutoToolResult

/// The outcome of a `streamCompletionWithTools` call — same shape as
/// `ClaudeToolChoiceResult`, just named separately since the streamed and
/// non-streamed multi-tool paths are independent call sites today.
enum StreamedAutoToolResult {
    case toolUse(name: String, input: [String: Any])
    case text(String)
}

// MARK: - ClaudeAPIError

enum ClaudeAPIError: LocalizedError {
    case invalidResponse
    case malformedResponse
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int)
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .unauthorized:
            return "The claude-chat function rejected this session. Try signing in again."
        case .rateLimited:
            return "Claude API rate limit hit. Try again in a moment."
        case .serverError(let code):
            return "Anthropic server error (\(code)). Try again shortly."
        case .httpError(let code):
            return "Unexpected HTTP error: \(code)."
        default:
            return "An unexpected error occurred with the Claude API."
        }
    }
}
