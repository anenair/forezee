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

final class ClaudeAPIClient {

    // MARK: - Configuration

    private let apiKey: String
    private let baseURL = URL(string: "https://api.anthropic.com/v1/messages")!
    private let anthropicVersion = "2023-06-01"

    private let urlSession: URLSession

    init() {
        self.apiKey = Bundle.main.infoDictionary?["CLAUDE_API_KEY"] as? String ?? ""

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 60
        config.timeoutIntervalForResource = 300
        self.urlSession = URLSession(configuration: config)
    }

    // MARK: - Streaming Completion

    /// Stream a response token-by-token from the Claude Messages API.
    /// Returns the full assembled response string when the stream ends.
    func streamCompletion(
        model: KaiModel,
        systemPrompt: String,
        messages: [KaiMessage],
        onToken: @escaping (String) -> Void
    ) async throws -> String {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("sk-ant-your") else {
            throw ClaudeAPIError.apiKeyNotConfigured
        }

        let request = try buildRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            stream: true
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
        systemPrompt: String,
        userMessage: String
    ) async throws -> String {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("sk-ant-your") else {
            throw ClaudeAPIError.apiKeyNotConfigured
        }

        let messages = [KaiMessage(role: .user, content: userMessage)]
        let request = try buildRequest(
            model: model,
            systemPrompt: systemPrompt,
            messages: messages,
            stream: false
        )

        let (data, response) = try await urlSession.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        return try parseNonStreamResponse(data)
    }

    // MARK: - Tool Use (structured output)

    /// Forces Claude to respond via a single named tool, guaranteeing a
    /// structured (JSON) result instead of free-form prose — used for real
    /// LLM understanding of mid-workout voice commands (intent + extracted
    /// weight/reps) without falling back to hand-rolled pattern matching.
    func completeWithTool(
        model: KaiModel,
        systemPrompt: String,
        userMessage: String,
        tool: ClaudeTool,
        maxTokens: Int = 300
    ) async throws -> [String: Any] {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("sk-ant-your") else {
            throw ClaudeAPIError.apiKeyNotConfigured
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": [["role": "user", "content": userMessage]],
            "tools": [[
                "name": tool.name,
                "description": tool.description,
                "input_schema": tool.inputSchema,
            ]],
            "tool_choice": ["type": "tool", "name": tool.name],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

        return try parseToolUseResponse(data, toolName: tool.name)
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
        systemPrompt: String,
        messages: [KaiMessage],
        tools: [ClaudeTool],
        maxTokens: Int = 1024
    ) async throws -> ClaudeToolChoiceResult {
        guard !apiKey.isEmpty, !apiKey.hasPrefix("sk-ant-your") else {
            throw ClaudeAPIError.apiKeyNotConfigured
        }
        guard !tools.isEmpty else {
            // No skills loaded — same shape as "Claude chose not to use a tool."
            let text = try await complete(
                model: model,
                systemPrompt: systemPrompt,
                userMessage: messages.last?.content ?? ""
            )
            return .text(text)
        }

        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": maxTokens,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] },
            "tools": tools.map { ["name": $0.name, "description": $0.description, "input_schema": $0.inputSchema] },
            "tool_choice": ["type": "auto"],
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await urlSession.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw ClaudeAPIError.invalidResponse
        }
        try validateStatusCode(httpResponse.statusCode)

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

    private func buildRequest(
        model: KaiModel,
        systemPrompt: String,
        messages: [KaiMessage],
        stream: Bool
    ) throws -> URLRequest {
        var request = URLRequest(url: baseURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue(anthropicVersion, forHTTPHeaderField: "anthropic-version")

        let body: [String: Any] = [
            "model": model.rawValue,
            "max_tokens": 1024,
            "stream": stream,
            "system": systemPrompt,
            "messages": messages.map { ["role": $0.role.rawValue, "content": $0.content] }
        ]

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

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

    private func parseNonStreamResponse(_ data: Data) throws -> String {
        guard let obj = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let content = obj["content"] as? [[String: Any]],
              let first = content.first,
              let text = first["text"] as? String else {
            throw ClaudeAPIError.malformedResponse
        }
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

// MARK: - ClaudeAPIError

enum ClaudeAPIError: LocalizedError {
    case apiKeyNotConfigured
    case invalidResponse
    case malformedResponse
    case unauthorized
    case rateLimited
    case serverError(statusCode: Int)
    case httpError(statusCode: Int)

    var errorDescription: String? {
        switch self {
        case .apiKeyNotConfigured:
            return "Claude API key not configured. Add it to Secrets.xcconfig."
        case .unauthorized:
            return "Invalid Claude API key. Check Secrets.xcconfig."
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
