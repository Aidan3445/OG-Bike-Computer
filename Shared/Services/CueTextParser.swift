//
//  CueTextParser.swift
//  OG Bike Computer
//
//  Pulls the street-name portion out of a cue-sheet instruction string and
//  lets edits substitute a new street name back into the original phrasing.
//  Examples:
//      "Turn left onto Main Street"           -> "Main Street"
//      "Continue on Elm Ave"                  -> "Elm Ave"
//      "At the roundabout, take the 3rd exit onto Birch Ln" -> "Birch Ln"
//      "Slight right toward Maple Ct"         -> "Maple Ct"
//  Patterns are matched longest-first so " onto " wins over " on " etc.
//

import Foundation

enum CueTextParser {

    /// Prepositions that precede a street name, ordered so longer/more specific
    /// patterns match first (avoiding "on" eating "onto").
    private static let prepositions: [String] = [
        "onto", "towards", "toward", "into", "on"
    ]

    /// Punctuation that terminates a street name when we're scanning forward.
    private static let terminators: Set<Character> = [",", ";", ".", "!"]

    /// The result of parsing a cue instruction.
    struct ParsedCue {
        let prefix: String        // everything before the street name (incl. trailing " onto ")
        let streetName: String    // just the name
        let suffix: String        // anything after — usually empty
    }

    /// Try to identify the street-name portion of a cue description.
    /// Returns nil when no recognizable preposition is present.
    static func parse(_ text: String) -> ParsedCue? {
        for prep in prepositions {
            let pattern = " \(prep) "
            guard let range = text.range(of: pattern, options: .caseInsensitive) else { continue }
            let startOfName = range.upperBound
            let after = text[startOfName...]
            let endOfName = after.firstIndex(where: { terminators.contains($0) }) ?? after.endIndex
            let candidate = String(after[after.startIndex..<endOfName])
                .trimmingCharacters(in: .whitespaces)
            guard !candidate.isEmpty else { continue }
            let prefix = String(text[text.startIndex..<startOfName])
            let suffix = String(after[endOfName...])
            return ParsedCue(prefix: prefix, streetName: candidate, suffix: suffix)
        }
        return nil
    }

    /// Just the street-name portion. Returns nil when nothing parseable.
    static func streetName(in text: String) -> String? {
        parse(text)?.streetName
    }

    /// Replace the street name in `text` while preserving the surrounding
    /// phrasing (so "Turn left onto Main St" with `new = "Main Street"`
    /// becomes "Turn left onto Main Street"). If `text` has no parseable
    /// street name, returns `new` on its own — callers can use this when the
    /// only goal is to apply the new name.
    static func substitute(in text: String, with new: String) -> String {
        guard let parsed = parse(text) else { return new }
        return parsed.prefix + new + parsed.suffix
    }

    /// Generate an announcement-style cue from a direction + street name —
    /// used for newly-added Missing turns where there's no original phrasing
    /// to substitute into.
    static func compose(direction: TurnDirection, streetName: String) -> String {
        let trimmed = streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            return verb(for: direction)
        }
        return "\(verb(for: direction)) onto \(trimmed)"
    }

    private static func verb(for direction: TurnDirection) -> String {
        switch direction {
        case .sharpLeft:    return "Sharp left"
        case .left:         return "Turn left"
        case .slightLeft:   return "Slight left"
        case .straight:     return "Continue"
        case .slightRight:  return "Slight right"
        case .right:        return "Turn right"
        case .sharpRight:   return "Sharp right"
        case .uTurn:        return "Make a u-turn"
        }
    }
}
