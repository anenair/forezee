// ============================================================
// Skill.swift
// Forzee — Core/AI/Skills
//
// One Kai capability, fully described by a single bundled .md
// file under Forzee/Resources/Skills/ — frontmatter (name /
// description / model), a fenced ```json block for the tool's
// input schema, and a prompt body with {{placeholder}} tokens
// filled from live app data at call time. This is the format
// SkillLoader.reload() parses; see that file for how a skill
// gets from "a file in the folder" to something Claude can pick
// with no registration step anywhere in Swift.
//
// Distinct from Claude Code's own unrelated .md-file skill
// system — this one is interpreted entirely by the Forzee app
// at runtime, not by the coding harness.
// ============================================================

import Foundation

// MARK: - Skill

struct Skill {
    let name: String
    let description: String
    let model: KaiModel
    let toolSchema: [String: Any]
    let promptTemplate: String

    /// The Claude tool-use definition this skill presents — to a forced
    /// single-tool call (KaiEngine.run(skill:)) or as one candidate among
    /// several Claude can choose from (KaiEngine.discoverAndRunSkill).
    var tool: ClaudeTool {
        ClaudeTool(name: name, description: description, inputSchema: toolSchema)
    }

    /// Fills {{key}} tokens in the prompt body with live values. An
    /// unrecognized placeholder is left as literal text rather than
    /// thrown — a typo'd token should be visible in testing (it'll show up
    /// verbatim in the prompt), not silently swallowed into an empty string.
    func renderedPrompt(placeholders: [String: String]) -> String {
        var text = promptTemplate
        for (key, value) in placeholders {
            text = text.replacingOccurrences(of: "{{\(key)}}", with: value)
        }
        return text
    }
}

// MARK: - SkillParseError

enum SkillParseError: LocalizedError {
    case missingFrontmatter
    case missingField(String)
    case missingToolSchema
    case invalidToolSchemaJSON
    case unknownModel(String)

    var errorDescription: String? {
        switch self {
        case .missingFrontmatter:
            return "Skill file is missing its --- frontmatter block."
        case .missingField(let field):
            return "Skill frontmatter is missing required field \"\(field)\"."
        case .missingToolSchema:
            return "Skill file is missing its fenced ```json tool schema block."
        case .invalidToolSchemaJSON:
            return "Skill's tool schema block isn't valid JSON."
        case .unknownModel(let value):
            return "Skill frontmatter model \"\(value)\" isn't \"sonnet\" or \"opus\"."
        }
    }
}

// MARK: - SkillParser

/// Parses one skill's raw .md content. No YAML dependency — frontmatter is
/// just flat `key: value` lines between two `---` markers, which is all
/// three fields (name/description/model) ever need.
///
/// Format:
/// ```
/// ---
/// name: skill_name
/// description: one line Claude sees when deciding whether this skill applies
/// model: sonnet | opus
/// ---
///
/// ```json
/// { "type": "object", "properties": { ... }, "required": [...] }
/// ```
///
/// The prompt body, with {{placeholders}} filled at call time.
/// ```
enum SkillParser {

    static func parse(_ raw: String) throws -> Skill {
        let lines = raw.components(separatedBy: "\n")

        guard lines.first?.trimmingCharacters(in: .whitespaces) == "---",
              let closingIndex = lines.dropFirst().firstIndex(where: {
                  $0.trimmingCharacters(in: .whitespaces) == "---"
              }) else {
            throw SkillParseError.missingFrontmatter
        }

        var fields: [String: String] = [:]
        for line in lines[1..<closingIndex] {
            guard let colonIndex = line.firstIndex(of: ":") else { continue }
            let key = line[line.startIndex..<colonIndex].trimmingCharacters(in: .whitespaces)
            let value = line[line.index(after: colonIndex)...].trimmingCharacters(in: .whitespaces)
            guard !key.isEmpty else { continue }
            fields[key] = value
        }

        guard let name = fields["name"], !name.isEmpty else {
            throw SkillParseError.missingField("name")
        }
        guard let description = fields["description"], !description.isEmpty else {
            throw SkillParseError.missingField("description")
        }
        guard let modelRaw = fields["model"], !modelRaw.isEmpty else {
            throw SkillParseError.missingField("model")
        }
        guard let model = kaiModel(from: modelRaw) else {
            throw SkillParseError.unknownModel(modelRaw)
        }

        // Everything after the closing "---": the fenced json block, then the prompt body.
        let body = lines[(closingIndex + 1)...].joined(separator: "\n")

        guard let jsonStart = body.range(of: "```json"),
              let jsonEnd = body.range(of: "```", range: jsonStart.upperBound..<body.endIndex) else {
            throw SkillParseError.missingToolSchema
        }

        let jsonText = body[jsonStart.upperBound..<jsonEnd.lowerBound]
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let jsonData = jsonText.data(using: .utf8),
              let toolSchema = try? JSONSerialization.jsonObject(with: jsonData) as? [String: Any] else {
            throw SkillParseError.invalidToolSchemaJSON
        }

        let promptTemplate = body[jsonEnd.upperBound...]
            .trimmingCharacters(in: .whitespacesAndNewlines)

        return Skill(
            name: name,
            description: description,
            model: model,
            toolSchema: toolSchema,
            promptTemplate: promptTemplate
        )
    }

    private static func kaiModel(from raw: String) -> KaiModel? {
        switch raw.lowercased() {
        case "sonnet": return .sonnet
        case "opus":   return .opus
        default:       return nil
        }
    }
}
