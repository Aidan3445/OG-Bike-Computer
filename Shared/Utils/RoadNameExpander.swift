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

    private static let directionAbbreviations: [(pattern: String, replacement: String)] = [
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

    private static let roadAbbreviations: [(pattern: String, replacement: String)] = [
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
    static func expand(_ text: String) -> String {
        var result = text

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
}
