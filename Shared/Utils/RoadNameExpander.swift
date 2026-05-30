//
//  RoadNameExpander.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/29/26.
//

import Foundation

/// Expands common road and direction abbreviations for more natural voice and display output.
/// e.g. "Turn right onto W School St" → "Turn right onto West School Street"
enum RoadNameExpander {

    // MARK: - Direction abbreviations (case-insensitive, word-boundary match)

    nonisolated private static let directionAbbreviations: [(pattern: String, replacement: String)] = [
        ("\\bN\\b\\.?", "North"),
        ("\\bS\\b\\.?", "South"),
        ("\\bE\\b\\.?", "East"),
        ("\\bW\\b\\.?", "West"),
        ("\\bNE\\b\\.?", "Northeast"),
        ("\\bNW\\b\\.?", "Northwest"),
        ("\\bSE\\b\\.?", "Southeast"),
        ("\\bSW\\b\\.?", "Southwest"),
    ]

    // MARK: - Road type abbreviations

    nonisolated private static let roadAbbreviations: [(pattern: String, replacement: String)] = [
        ("\\bSt\\b\\.?", "Street"),
        ("\\bAve\\b\\.?", "Avenue"),
        ("\\bBlvd\\b\\.?", "Boulevard"),
        ("\\bDr\\b\\.?", "Drive"),
        ("\\bRd\\b\\.?", "Road"),
        ("\\bLn\\b\\.?", "Lane"),
        ("\\bCt\\b\\.?", "Court"),
        ("\\bPl\\b\\.?", "Place"),
        ("\\bPkwy\\b\\.?", "Parkway"),
        ("\\bHwy\\b\\.?", "Highway"),
        ("\\bCir\\b\\.?", "Circle"),
        ("\\bTrl\\b\\.?", "Trail"),
        ("\\bTer\\b\\.?", "Terrace"),
        ("\\bWay\\b\\.?", "Way"),
        ("\\bSq\\b\\.?", "Square"),
        ("\\bExpy\\b\\.?", "Expressway"),
        ("\\bFwy\\b\\.?", "Freeway"),
        ("\\bBrg\\b\\.?", "Bridge"),
        ("\\bCrk\\b\\.?", "Creek"),
        ("\\bMtn\\b\\.?", "Mountain"),
        ("\\bPt\\b\\.?", "Point"),
        ("\\bFt\\b\\.?", "Fort"),
        ("\\bMt\\b\\.?", "Mount"),
    ]

    /// Expand all recognized abbreviations in a road description.
    /// Pure text manipulation — explicitly nonisolated so it can be called
    /// from nonisolated contexts (e.g. `ProcessedRoute`'s value-type helpers)
    /// without crossing the main-actor boundary.
    nonisolated static func expand(_ text: String) -> String {
        var result = text

        // A slash between two street names ("Main St/N MLK Blvd") indicates the
        // road has two names. Voice it as " slash " so the secondary name reads
        // as a distinct street rather than running together.
        result = expandSlash(in: result)

        // Expand direction abbreviations first (they appear before the street name)
        for abbr in directionAbbreviations {
            if let regex = try? NSRegularExpression(pattern: abbr.pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: abbr.replacement
                )
            }
        }

        // Expand road type abbreviations
        for abbr in roadAbbreviations {
            if let regex = try? NSRegularExpression(pattern: abbr.pattern, options: []) {
                result = regex.stringByReplacingMatches(
                    in: result,
                    range: NSRange(result.startIndex..., in: result),
                    withTemplate: abbr.replacement
                )
            }
        }

        return result
    }

    /// Replace "/" between alphanumeric tokens with " slash ", collapsing any
    /// surrounding whitespace so "A / B", "A /B", and "A/B" all read the same.
    nonisolated private static func expandSlash(in text: String) -> String {
        guard let regex = try? NSRegularExpression(
            pattern: "(\\w)\\s*/\\s*(\\w)",
            options: []
        ) else { return text }
        return regex.stringByReplacingMatches(
            in: text,
            range: NSRange(text.startIndex..., in: text),
            withTemplate: "$1 slash $2"
        )
    }
}
