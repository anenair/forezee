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
