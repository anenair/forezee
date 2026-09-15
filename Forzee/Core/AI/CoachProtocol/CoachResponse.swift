// ============================================================
// CoachResponse.swift
// Forzee — Core/AI/CoachProtocol
//
// The versioned, typed contract between Kai (the LLM coaching
// layer) and the app — replacing an earlier, narrower shape
// (text/workout/note/actions as one flat object) that couldn't
// grow a new response kind without redefining itself. Every
// assistant turn in Coach chat is now one CoachResponse: an
// ordered list of typed CoachBlocks, plus an optional list of
// structured CoachActions the user can trigger.
//
// This is a PROPOSAL layer, not application state. A WorkoutBlock
// here is Kai's suggestion — it only becomes a real, persisted
// workout once WorkoutBuilder converts it into a GeneratedWorkout
// and the user actually starts it (see CoachActionExecutor). The
// LLM never writes to the database and never becomes the app's
// state machine.
//
// Backward compatibility: KaiMessage.content / coach_messages.content
// is still just a String column — nothing about persistence changed.
// A NEW assistant message stores this type's JSON encoding in that
// string. An OLD message (or any reply that, for whatever reason,
// isn't valid protocol JSON) is not an error — `parse(legacyContent:)`
// wraps it as a single-TextBlock CoachResponse, so every existing
// stored message and every future response flow through the exact
// same rendering path (see CoachBlockRenderer).
// ============================================================

import Foundation

// MARK: - CoachResponse

struct CoachResponse: Codable {
    var protocolVersion: String
    var messageId: String
    var blocks: [CoachBlock]
    var actions: [CoachAction]?
    var metadata: CoachResponseMetadata?

    static let currentProtocolVersion = "1.0"

    init(
        protocolVersion: String = CoachResponse.currentProtocolVersion,
        messageId: String = UUID().uuidString,
        blocks: [CoachBlock],
        actions: [CoachAction]? = nil,
        metadata: CoachResponseMetadata? = nil
    ) {
        self.protocolVersion = protocolVersion
        self.messageId = messageId
        self.blocks = blocks
        self.actions = actions
        self.metadata = metadata
    }

    // MARK: - Backward Compatibility

    /// Turns whatever is stored in KaiMessage.content into a CoachResponse
    /// — the one place old and new messages reconcile. Anything that
    /// doesn't decode as protocol JSON (every message sent before this
    /// protocol existed, any user-typed message, or a raw string from a
    /// call site that doesn't build one) becomes a single plain TextBlock
    /// instead of a rendering error.
    static func parse(legacyContent content: String) -> CoachResponse {
        if let data = content.data(using: .utf8),
           let decoded = try? JSONDecoder().decode(CoachResponse.self, from: data) {
            return decoded
        }
        return CoachResponse(blocks: [.text(TextBlock(content: content))])
    }

    /// JSON-encodes self for storage in KaiMessage.content — the wire
    /// format is unchanged (a String column); this is just what now goes
    /// inside it.
    func encodedContent() -> String {
        guard let data = try? JSONEncoder().encode(self),
              let string = String(data: data, encoding: .utf8) else {
            // Unreachable in practice (every value in this type is
            // JSON-safe) — fall back to the plainest possible text rather
            // than lose the message entirely.
            return plainTextSummary
        }
        return string
    }

    /// A flattened, spoken-friendly summary — used for voice mode's TTS
    /// and as the encode fallback above. Never shown in the chat UI
    /// itself; CoachBlockRenderer renders every block natively instead of
    /// a text summary of them.
    var plainTextSummary: String {
        blocks.map { block -> String in
            switch block {
            case .text(let b):         return b.content
            case .coachingNote(let b): return b.content
            case .workout(let b):
                let title = b.workout.title.isEmpty ? "a workout" : b.workout.title
                return "Here's \(title) — \(b.workout.exercises.count) exercises."
            case .progress(let b):     return "\(b.title): \(b.current)\(b.unit)."
            case .confirmation(let b): return b.message
            case .unknown:              return ""
            }
        }
        .filter { !$0.isEmpty }
        .joined(separator: " ")
    }
}

// MARK: - CoachResponseMetadata

struct CoachResponseMetadata: Codable {
    var intent: CoachIntent?
}

/// A light, optional classification of what a reply is doing —
/// informational only right now; nothing branches on it yet. Reserved for
/// future routing (e.g. surfacing intent in analytics or letting the UI
/// treat a check-in differently from a workout proposal later).
enum CoachIntent: Equatable {
    case workoutProposal
    case coachingAdvice
    case checkIn
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "workout_proposal": self = .workoutProposal
        case "coaching_advice":  self = .coachingAdvice
        case "check_in":         self = .checkIn
        default:                 self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .workoutProposal: return "workout_proposal"
        case .coachingAdvice:  return "coaching_advice"
        case .checkIn:         return "check_in"
        case .unknown(let v):  return v
        }
    }
}

extension CoachIntent: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - CoachBlock

/// The discriminated union of everything Kai can send back. Implemented
/// (schema + a real renderer) for v1: text, workout, coaching_note.
/// Decode-ready but not yet interactive: progress, confirmation — a
/// future call site can start emitting either without any renderer
/// changes. `.unknown` is the true forward-compat catch-all: any block
/// "type" not listed above (a future ExerciseBlock/MetricBlock/AlertBlock,
/// or anything invented later) decodes safely and simply isn't rendered,
/// rather than failing the whole message. Adding real support for one of
/// those later is a new `case` + one new renderer arm — never a rewrite
/// of this type or of CoachBlockRenderer's switch.
enum CoachBlock: Equatable {
    case text(TextBlock)
    case workout(WorkoutBlock)
    case coachingNote(CoachingNoteBlock)
    case progress(ProgressBlock)
    case confirmation(ConfirmationBlock)
    case unknown(type: String)

    private enum TypeKey: String, CodingKey { case type }
}

extension CoachBlock: Decodable {
    init(from decoder: Decoder) throws {
        let typeContainer = try decoder.container(keyedBy: TypeKey.self)
        let type = try typeContainer.decode(String.self, forKey: .type)
        switch type {
        case "text":          self = .text(try TextBlock(from: decoder))
        case "workout":       self = .workout(try WorkoutBlock(from: decoder))
        case "coaching_note": self = .coachingNote(try CoachingNoteBlock(from: decoder))
        case "progress":      self = .progress(try ProgressBlock(from: decoder))
        case "confirmation":  self = .confirmation(try ConfirmationBlock(from: decoder))
        default:              self = .unknown(type: type)
        }
    }
}

extension CoachBlock: Encodable {
    func encode(to encoder: Encoder) throws {
        switch self {
        case .text(let b):         try b.encode(to: encoder)
        case .workout(let b):      try b.encode(to: encoder)
        case .coachingNote(let b): try b.encode(to: encoder)
        case .progress(let b):     try b.encode(to: encoder)
        case .confirmation(let b): try b.encode(to: encoder)
        case .unknown(let type):
            var container = encoder.container(keyedBy: TypeKey.self)
            try container.encode(type, forKey: .type)
        }
    }
}

// MARK: - TextBlock

/// Natural conversation. The app may render basic Markdown-lite (a "- "
/// bullet convention — see KaiSystemPrompt's Formatting rule) inside this
/// block's content; structured fitness data never belongs here, that's
/// what WorkoutBlock/ProgressBlock/etc. are for.
struct TextBlock: Codable, Equatable {
    var type: String = "text"
    var content: String
}

// MARK: - CoachingNoteBlock

enum CoachingNoteSeverity: String, Codable, Equatable {
    case info
    case tip
    case caution
}

struct CoachingNoteBlock: Equatable {
    var type: String = "coaching_note"
    var severity: CoachingNoteSeverity
    var content: String

    init(severity: CoachingNoteSeverity, content: String) {
        self.severity = severity
        self.content = content
    }
}

extension CoachingNoteBlock: Codable {
    private enum CodingKeys: String, CodingKey { case type, severity, content }

    /// An unrecognized severity string collapses to `.info` rather than
    /// failing the decode — "do not allow the LLM to arbitrarily invent
    /// styling" means an invented value is *ignored*, not honored, and
    /// also isn't allowed to sink the whole note.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let severityRaw = try container.decodeIfPresent(String.self, forKey: .severity) ?? "info"
        severity = CoachingNoteSeverity(rawValue: severityRaw) ?? .info
        content = try container.decode(String.self, forKey: .content)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(type, forKey: .type)
        try container.encode(severity.rawValue, forKey: .severity)
        try container.encode(content, forKey: .content)
    }
}

// MARK: - ProgressBlock

/// Architecture-ready for v1 — decodable and renderable (see
/// CoachBlockRenderer), but no call site emits one yet. The UI owns the
/// visualization entirely; the LLM only ever supplies these four values.
struct ProgressBlock: Codable, Equatable {
    var type: String = "progress"
    var title: String
    var metric: String
    var current: Double
    var previous: Double?
    var unit: String
}

// MARK: - ConfirmationBlock

/// Architecture-ready for v1 — decodable and renders as a read-only card,
/// but no call site emits one and no confirm/cancel handling is wired up
/// yet. Reserved for a future state-changing proposal ("Replace Barbell
/// Bench Press with Dumbbell Bench Press?").
struct ConfirmationBlock: Codable, Equatable {
    var type: String = "confirmation"
    var title: String
    var message: String
}

// MARK: - CoachAction

/// A structured action the user can trigger from a reply. Only
/// `build_workout` is actually executable in v1 (see CoachActionExecutor)
/// — every other case in CoachActionType exists so the schema and model
/// can grow into them later without another protocol version bump.
/// CoachResponseValidator.isPermitted decides what's real; this struct is
/// just data, never a standing grant to do anything.
struct CoachAction: Codable, Identifiable, Equatable {
    var id: String
    var type: CoachActionType
    var label: String
    /// Flat string key/values only — enough for a future action that
    /// needs one (v1's build_workout doesn't: it reads the workout to
    /// build straight off this response's own WorkoutBlock, never from a
    /// payload). Deliberately not a richer JSON-value type — that would
    /// pull in a dependency (Supabase's AnyJSON, or a hand-rolled
    /// equivalent) for a shape nothing needs yet.
    var payload: [String: String]?
}

/// RawRepresentable-with-fallback, same pattern as CoachIntent — an action
/// type the app doesn't recognize (a future one added to the roadmap
/// list, or a hallucinated one) decodes as `.unknown` instead of failing,
/// and CoachResponseValidator.isPermitted always rejects it.
enum CoachActionType: Equatable {
    case buildWorkout
    case startWorkout
    case replaceExercise
    case modifyWorkout
    case logSet
    case skipExercise
    case startTimer
    case finishWorkout
    case showExercise
    case viewProgress
    case unknown(String)

    init(rawValue: String) {
        switch rawValue {
        case "build_workout":    self = .buildWorkout
        case "start_workout":    self = .startWorkout
        case "replace_exercise": self = .replaceExercise
        case "modify_workout":   self = .modifyWorkout
        case "log_set":          self = .logSet
        case "skip_exercise":    self = .skipExercise
        case "start_timer":      self = .startTimer
        case "finish_workout":   self = .finishWorkout
        case "show_exercise":    self = .showExercise
        case "view_progress":    self = .viewProgress
        default:                 self = .unknown(rawValue)
        }
    }

    var rawValue: String {
        switch self {
        case .buildWorkout:    return "build_workout"
        case .startWorkout:    return "start_workout"
        case .replaceExercise: return "replace_exercise"
        case .modifyWorkout:   return "modify_workout"
        case .logSet:          return "log_set"
        case .skipExercise:    return "skip_exercise"
        case .startTimer:      return "start_timer"
        case .finishWorkout:   return "finish_workout"
        case .showExercise:    return "show_exercise"
        case .viewProgress:    return "view_progress"
        case .unknown(let v):  return v
        }
    }
}

extension CoachActionType: Codable {
    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }
    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

// MARK: - Tool Schema (Schema-Enforced Structured Output)

/// Only `blocks`/`actions`/`metadata` are asked of the model — `messageId`
/// and `protocolVersion` are app-assigned (see `from(toolInput:)` below),
/// same reasoning as GeneratedWorkout never trusting Claude for `id` or
/// `generatedAt`. Intentionally a flat, permissive shape (every block
/// type's possible fields listed as siblings under one object) rather
/// than a strict JSON Schema `oneOf` — this mirrors every bundled skill's
/// own tool schema already in this codebase (see any file under
/// Forzee/Resources/Skills/) and
/// is the shape Anthropic's tool-use is most reliable with in practice.
///
/// Written as a JSON string and parsed with JSONSerialization, exactly
/// like SkillParser parses a skill's fenced ```json block — deliberately
/// NOT a hand-nested Swift `[String: Any]` dictionary literal. Every
/// existing tool schema in this codebase already comes from real parsed
/// JSON text for the same reason: a heterogeneous dictionary literal
/// nested this deeply is exactly the shape the Swift type-checker can
/// silently misinfer or choke on, and there's no compiler here to catch
/// it before it ships. Plain JSON text has no such ambiguity.
extension CoachResponse {

    /// The tool Kai's main conversational reply is forced through (see
    /// KaiEngine.sendCoachMessage) — every reply comes back through this
    /// shape, never free-form prose.
    static var tool: ClaudeTool {
        ClaudeTool(
            name: "send_coach_response",
            description: "Send your reply to the user as structured content blocks, optionally with actions they can trigger.",
            inputSchema: toolInputSchema
        )
    }

    private static let toolInputSchema: [String: Any] = {
        guard let data = toolInputSchemaJSON.data(using: .utf8),
              let schema = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            // Unreachable — the literal below is fixed, valid JSON. If this
            // ever fires, requiring at least a text block is still a schema
            // the model can satisfy, rather than a hard crash on launch.
            return ["type": "object", "properties": ["blocks": ["type": "array"]], "required": ["blocks"]]
        }
        return schema
    }()

    private static let toolInputSchemaJSON = """
    {
      "type": "object",
      "properties": {
        "blocks": {
          "type": "array",
          "description": "Ordered content blocks making up this reply. Always include at least one.",
          "items": {
            "type": "object",
            "properties": {
              "type": {
                "type": "string",
                "enum": ["text", "workout", "coaching_note", "progress", "confirmation"]
              },
              "content": { "type": "string", "description": "For type=text or type=coaching_note." },
              "severity": {
                "type": "string",
                "enum": ["info", "tip", "caution"],
                "description": "For type=coaching_note only."
              },
              "workout": {
                "type": "object",
                "description": "For type=workout only.",
                "properties": {
                  "title": { "type": "string" },
                  "estimatedDurationMinutes": { "type": "integer" },
                  "exercises": {
                    "type": "array",
                    "items": {
                      "type": "object",
                      "properties": {
                        "name": { "type": "string" },
                        "notes": { "type": "string", "description": "Form cue or modification, if any." },
                        "prescription": {
                          "type": "object",
                          "description": "Exactly one prescription shape, discriminated by its own \\"type\\".",
                          "properties": {
                            "type": { "type": "string", "enum": ["reps", "duration", "rep_range"] },
                            "sets": { "type": "integer" },
                            "reps": { "type": "integer", "description": "Required when type=reps." },
                            "repsMin": { "type": "integer", "description": "Required when type=rep_range." },
                            "repsMax": { "type": "integer", "description": "Required when type=rep_range." },
                            "durationSeconds": { "type": "integer", "description": "Required when type=duration." },
                            "restSeconds": { "type": "integer" },
                            "rir": { "type": "integer", "description": "Reps in reserve, optional." }
                          },
                          "required": ["type", "sets"]
                        }
                      },
                      "required": ["name", "prescription"]
                    }
                  }
                },
                "required": ["title", "exercises"]
              },
              "title": { "type": "string", "description": "For type=progress or type=confirmation." },
              "metric": { "type": "string", "description": "For type=progress only." },
              "current": { "type": "number", "description": "For type=progress only." },
              "previous": { "type": "number", "description": "For type=progress only." },
              "unit": { "type": "string", "description": "For type=progress only." },
              "message": { "type": "string", "description": "For type=confirmation only." }
            },
            "required": ["type"]
          }
        },
        "actions": {
          "type": "array",
          "description": "Structured actions the user can trigger. Only these types actually do anything — every other action type will be ignored: build_workout (needs a workout block in the same reply), replace_exercise (payload naming the swap, reads better paired with a confirmation block), log_set (logs one real set against whichever exercise is CURRENTLY ACTIVE — never a named one — only with a real rep count or an explicit reuse-previous), start_workout (starts a repeat of a NAMED past workout — payload.workoutName — only when nothing is already in progress), modify_workout (removes a named exercise from the CURRENTLY ACTIVE session — payload.exerciseName), skip_exercise (marks the CURRENT exercise done with no sets — no payload needed), start_timer (starts a rest timer — payload.seconds), finish_workout (ends the CURRENTLY ACTIVE session — no payload needed, only once at least one set is actually logged), show_exercise (opens that exercise's history — payload.exerciseName, works for any exercise, no session needed), view_progress (switches to the Progress tab — no payload needed).",
          "items": {
            "type": "object",
            "properties": {
              "id": { "type": "string" },
              "type": {
                "type": "string",
                "enum": [
                  "build_workout", "replace_exercise", "log_set", "start_workout",
                  "modify_workout", "skip_exercise", "start_timer", "finish_workout",
                  "show_exercise", "view_progress"
                ]
              },
              "label": { "type": "string" },
              "payload": {
                "type": "object",
                "description": "Required for type=replace_exercise: exerciseName is the exercise to remove from the workout block in this same reply (must match one there exactly), replacementName is what to swap it in for. For type=log_set: reps is the rep count actually done (required unless sameAsPrevious is the literal string true); weight/weightUnit are the weight actually used (omit both for a bodyweight set); sameAsPrevious (the literal string true or false) reuses whichever of weight/reps isn't given here from the last logged set on the current exercise. For type=start_workout: workoutName names a past workout by its title, matched against the user's history. For type=modify_workout or type=show_exercise: exerciseName names the exercise (modify_workout removes it from the current session; show_exercise just opens its history, no session needed). For type=start_timer: seconds is how long to rest, as a string.",
                "properties": {
                  "exerciseName": { "type": "string" },
                  "replacementName": { "type": "string" },
                  "reps": { "type": "string" },
                  "weight": { "type": "string" },
                  "weightUnit": { "type": "string", "enum": ["lbs", "kg"] },
                  "sameAsPrevious": { "type": "string", "enum": ["true", "false"] },
                  "workoutName": { "type": "string" },
                  "seconds": { "type": "string" }
                }
              }
            },
            "required": ["id", "type", "label"]
          }
        },
        "metadata": {
          "type": "object",
          "properties": {
            "intent": {
              "type": "string",
              "enum": ["workout_proposal", "coaching_advice", "check_in"]
            }
          }
        }
      },
      "required": ["blocks"]
    }
    """
}

/// Decodes only what the model actually supplies — messageId/protocolVersion
/// are stamped by the app afterward (see `CoachResponse.tool`'s doc comment).
private struct RawCoachToolInput: Decodable {
    var blocks: [CoachBlock]
    var actions: [CoachAction]?
    var metadata: CoachResponseMetadata?
}

extension CoachResponse {
    /// Builds a full CoachResponse from a Claude tool_use input dict (see
    /// ClaudeAPIClient.completeWithForcedTool) — the point where SCHEMA
    /// validation actually happens: a malformed shape throws right here.
    /// The caller (KaiEngine.sendCoachMessage) catches that and returns a
    /// graceful fallback rather than ever propagating it as a crash.
    /// Domain validation (are these *values* sane) is a separate pass —
    /// see CoachResponseValidator.sanitize, always run on the result.
    static func from(toolInput: [String: Any]) throws -> CoachResponse {
        let data = try JSONSerialization.data(withJSONObject: toolInput)
        let raw = try JSONDecoder().decode(RawCoachToolInput.self, from: data)
        return CoachResponse(blocks: raw.blocks, actions: raw.actions, metadata: raw.metadata)
    }
}
