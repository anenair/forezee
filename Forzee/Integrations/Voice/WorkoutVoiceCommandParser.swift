// ============================================================
// WorkoutVoiceCommandParser.swift
// Forzee — Integrations/Voice
//
// Local, offline, no-LLM intent parsing for the small fixed set of
// mid-workout voice commands ("mark a set complete", "what's next",
// "how am I doing"). Deliberately NOT routed through KaiEngine.chat:
// during an actual set, a 1-3s Sonnet round-trip is a bad experience
// and a dead network shouldn't block logging a set you just did —
// same offline-first reasoning as the rest of the workout flow.
//
// This is pattern matching, not real NLU. It covers the phrasings
// in the brief plus close variants; anything else comes back
// `.unrecognized` and WorkoutTabView falls back to a real Kai chat
// call for open-ended questions.
//
// Relies on iOS Speech's default number formatting (it transcribes
// spoken numbers as digits — "eight reps" → "8 reps" — in normal
// use), with a small word-number fallback for when it doesn't.
// Multi-word weights like "one thirty five" (135) are NOT handled —
// genuine compound-number parsing is real NLU scope, not attempted.
// ============================================================

import Foundation

enum WorkoutVoiceIntent: Equatable {
    case logSet(LoggedSetDetails)
    case nextExercise
    case progress
    case unrecognized
}

struct LoggedSetDetails: Equatable {
    var weightValue: Double?
    var weightUnit: WeightUnit?
    var reps: Int?
    var sameAsPrevious: Bool = false
}

enum WorkoutVoiceCommandParser {

    static func parse(_ rawTranscript: String) -> WorkoutVoiceIntent {
        let text = normalize(rawTranscript)
        guard !text.isEmpty else { return .unrecognized }

        if matchesAny(text, patterns: nextExercisePatterns) {
            return .nextExercise
        }
        if matchesAny(text, patterns: progressPatterns) {
            return .progress
        }

        let sameAsPrevious = matchesAny(text, patterns: sameAsPreviousPatterns)
        let weight = extractWeight(from: text)
        let reps = extractReps(from: text)
        let looksLikeLogSet = sameAsPrevious
            || weight != nil
            || reps != nil
            || matchesAny(text, patterns: markSetPatterns)

        if looksLikeLogSet {
            return .logSet(LoggedSetDetails(
                weightValue: weight?.value,
                weightUnit: weight?.unit,
                reps: reps,
                sameAsPrevious: sameAsPrevious
            ))
        }

        return .unrecognized
    }

    // MARK: - Patterns

    private static let nextExercisePatterns = [
        "next exercise", "what's next", "what is next", "what should i do next",
        "what do i do next",
    ]

    private static let progressPatterns = [
        "how am i doing", "how'm i doing", "how am i going", "how is it going",
        "how's it going", "my progress", "how many sets left", "how many left",
        "how many sets remaining", "how many exercises left",
    ]

    private static let sameAsPreviousPatterns = [
        "same as previous", "same as last", "same as before", "same weight",
    ]

    private static let markSetPatterns = [
        "mark a set", "mark one more set", "mark another set", "mark that set",
        "set complete", "set completed", "set done", "log a set", "log that set",
        "finished a set", "completed a set", "done with that set",
    ]

    // MARK: - Normalization

    private static func normalize(_ text: String) -> String {
        var result = text.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
        for (word, digit) in wordNumbers {
            result = result.replacingOccurrences(
                of: "\\b\(word)\\b",
                with: digit,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return result
    }

    /// Defensive fallback only — see file header. Covers the common single-word
    /// numbers a set/rep count or round-number weight would actually use.
    private static let wordNumbers: [(String, String)] = [
        ("one", "1"), ("two", "2"), ("three", "3"), ("four", "4"), ("five", "5"),
        ("six", "6"), ("seven", "7"), ("eight", "8"), ("nine", "9"), ("ten", "10"),
        ("eleven", "11"), ("twelve", "12"), ("thirteen", "13"), ("fourteen", "14"),
        ("fifteen", "15"), ("sixteen", "16"), ("seventeen", "17"), ("eighteen", "18"),
        ("nineteen", "19"), ("twenty", "20"), ("thirty", "30"), ("forty", "40"),
        ("fifty", "50"), ("sixty", "60"), ("seventy", "70"), ("eighty", "80"),
        ("ninety", "90"), ("hundred", "100"),
    ]

    // MARK: - Extraction

    private static func extractWeight(from text: String) -> (value: Double, unit: WeightUnit)? {
        let pattern = #"(\d+(?:\.\d+)?)\s*(lbs?|pounds?|kgs?|kilograms?|kilos?)\b"#
        guard let match = firstMatch(of: pattern, in: text), match.numberOfRanges >= 3,
              let valueRange = Range(match.range(at: 1), in: text),
              let unitRange = Range(match.range(at: 2), in: text),
              let value = Double(text[valueRange]) else {
            return nil
        }
        let unitToken = text[unitRange]
        let unit: WeightUnit = unitToken.hasPrefix("kg") || unitToken.hasPrefix("kilo") ? .kg : .lbs
        return (value, unit)
    }

    private static func extractReps(from text: String) -> Int? {
        let pattern = #"(\d+)\s*reps?\b"#
        guard let match = firstMatch(of: pattern, in: text), match.numberOfRanges >= 2,
              let valueRange = Range(match.range(at: 1), in: text) else {
            return nil
        }
        return Int(text[valueRange])
    }

    // MARK: - Regex Helpers

    private static func matchesAny(_ text: String, patterns: [String]) -> Bool {
        patterns.contains { text.contains($0) }
    }

    private static func firstMatch(of pattern: String, in text: String) -> NSTextCheckingResult? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else {
            return nil
        }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        return regex.firstMatch(in: text, options: [], range: range)
    }
}
