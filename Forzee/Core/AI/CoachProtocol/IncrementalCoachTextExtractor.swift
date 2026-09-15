// ============================================================
// IncrementalCoachTextExtractor.swift
// Forzee — Core/AI/CoachProtocol
//
// Pulls a live-typable preview out of an in-progress, not-yet-valid
// JSON buffer — the raw accumulated `partial_json` fragments from a
// streamed forced tool call (see
// ClaudeAPIClient.streamCompletionWithForcedTool). The buffer isn't
// parseable JSON until the whole object closes, so this never tries
// to parse it — it just scans for the first `"content":"..."` string
// value (the first text or coaching_note block, whichever Kai writes
// first) and reveals characters as that string closes, unescaping
// JSON escapes along the way.
//
// Only that ONE string ever gets a live preview. Once it closes, or
// if the response's first block isn't text/coaching_note at all,
// later blocks still arrive — they just pop in fully-formed with the
// rest of CoachBlockRenderer once the whole response completes,
// rather than typing themselves out. That's a UX nicety being
// deliberately kept simple, not a general streaming JSON parser.
// ============================================================

import Foundation

enum IncrementalCoachTextExtractor {

    /// Re-scans from scratch on every call. A chat reply's buffer is at
    /// most a few KB, so a fresh scan each time is cheap and far simpler
    /// than maintaining incremental scan state across calls — this is
    /// called once per streamed fragment, not in a hot loop.
    ///
    /// Returns nil until a `"content":"` key has actually appeared in the
    /// buffer yet (nothing to preview), otherwise everything of that
    /// string revealed so far.
    static func preview(fromRawJSON buffer: String) -> String? {
        // Tolerant of whitespace between the key, colon, and opening quote
        // (`"content": "..."` vs `"content":"..."`) rather than matching
        // one exact byte sequence — Claude's tool-use JSON is compact in
        // practice, but nothing guarantees that, and getting this wrong
        // only ever costs a missed preview, never a wrong one.
        guard let keyRange = buffer.range(of: "\"content\"") else { return nil }
        let afterKey = buffer[keyRange.upperBound...]
        guard let colonIndex = afterKey.firstIndex(of: ":") else { return nil }
        let afterColon = afterKey[afterKey.index(after: colonIndex)...]
        guard let openQuoteIndex = afterColon.firstIndex(where: { !$0.isWhitespace }),
              afterColon[openQuoteIndex] == "\"" else { return nil }

        var result = ""
        var iterator = afterColon[afterColon.index(after: openQuoteIndex)...].makeIterator()

        while let char = iterator.next() {
            if char == "\\" {
                // An escape sequence split across fragment boundaries (the
                // backslash arrived but not what follows it yet) — stop
                // without emitting a corrupted trailing character; the
                // next call re-scans from the start and picks it up whole.
                guard let escaped = iterator.next() else { break }
                switch escaped {
                case "n":  result.append("\n")
                case "t":  result.append("\t")
                case "r":  result.append("\r")
                case "\"": result.append("\"")
                case "\\": result.append("\\")
                case "/":  result.append("/")
                case "u":
                    var hex = ""
                    var incomplete = false
                    for _ in 0..<4 {
                        guard let digit = iterator.next() else { incomplete = true; break }
                        hex.append(digit)
                    }
                    // An incomplete \uXXXX at the buffer's edge — same
                    // reasoning as above, stop rather than guess. (Surrogate
                    // pairs for characters outside the Basic Multilingual
                    // Plane aren't joined back together here — a live
                    // preview nicety, not a full JSON string decoder.)
                    if incomplete { return result }
                    if let scalarValue = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(scalarValue) {
                        result.append(Character(scalar))
                    }
                default:
                    result.append(escaped)
                }
            } else if char == "\"" {
                break // The string closed — this block's content is complete.
            } else {
                result.append(char)
            }
        }
        return result
    }
}
