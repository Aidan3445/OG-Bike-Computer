//
//  CueDiff.swift
//  OG Bike Computer
//
//  Compares the raw waypoint cue sheet to the detector's calculated turns and
//  classifies each turn as Missing, Extra, or Good for the Cue Editor.
//
//  Notes:
//   - Matching is "within ~50m along the route AND direction agrees".
//   - A `Good` whose waypoint has no street name (description nil/empty) is
//     moved into the Missing bucket (per spec) and flagged as nameOnlyMissing
//     so the UI can still treat it like a waypoint (Skip/Edit, not Add).
//   - Output is purely a view of the route + current edits draft; persisting
//     decisions is the caller's job.
//

import Foundation

/// What kind of editor row this entry represents and which actions are valid.
enum CueEntryKind: Equatable {
    /// Detector found a turn the cue sheet doesn't have. Action: Add (or dismiss).
    case missingDetected
    /// Cue sheet has a Good turn but no street name. Action: Edit, Skip, Approve.
    case missingNameOnly
    /// Cue sheet has a cue the detector didn't see. Action: Skip, Edit, Approve.
    case extra
    /// Cue sheet and detector both saw the turn but disagreed on direction.
    /// Edit form opens pre-filled with the detector's suggestion. Action: Edit, Skip, Approve.
    case edit
    /// Cue sheet and detector agree. Action: Edit, Skip, Approve.
    case good
}

/// Identifier for an editor entry. Stable across reclassification (e.g. when an
/// edit moves a row's status but not its identity).
enum CueEntryID: Hashable {
    /// Backed by a waypoint cue (Good, Extra, or name-only Missing).
    case waypoint(UUID)
    /// Backed by a detector-only turn (pure Missing).
    case detected(Int)  // TurnPoint.index along the track
}

/// A single row in the Cue Editor.
struct CueEntry: Identifiable, Equatable {
    var id: CueEntryID
    var kind: CueEntryKind
    /// The TurnPoint to show on the map / use as the visual anchor.
    var turn: TurnPoint
    /// If this is a Good (or name-only Missing), this is the matched calculated
    /// turn — useful when an edit might want to snap to detector direction.
    var matchedCalculated: TurnPoint?

    static func == (lhs: CueEntry, rhs: CueEntry) -> Bool {
        // Equality by id + kind is sufficient for SwiftUI diffing.
        lhs.id == rhs.id && lhs.kind == rhs.kind
    }
}

struct CueClassification {
    var missing: [CueEntry]  // both pure-missing-detected and missing-name-only, sorted by distance
    var extra: [CueEntry]
    var edit: [CueEntry]     // waypoint + calc agree on location but disagree on direction
    var good: [CueEntry]

    var all: [CueEntry] {
        (missing + extra + edit + good).sorted { $0.turn.distanceFromStart < $1.turn.distanceFromStart }
    }
}

enum CueDiff {
    /// Match window along the route between a waypoint and a calculated turn.
    static let matchDistance: Double = 50  // meters

    /// Classify the raw turn lists. The classifier does NOT consult `CueEdits`:
    /// classification reflects the route's underlying truth. The editor view-model
    /// layers the user's per-row decision state on top of these entries.
    ///
    /// Three-pass matching:
    ///   1. Pair a waypoint to a calculated turn within `matchDistance` AND with
    ///      agreeing direction → Good (or missingNameOnly if no street name).
    ///   2. For unmatched waypoints, pair to a calculated turn within
    ///      `matchDistance` *ignoring direction* → Edit (or Good if the cue is
    ///      flagged as a roundabout/traffic-circle/rotary, since the detector
    ///      almost always reads those as a slight turn no matter what the cue
    ///      sheet says).
    ///   3. Leftovers: waypoints → Extra, calculated turns → missingDetected.
    static func classify(
        waypoints: [TurnPoint],
        calculated: [TurnPoint]
    ) -> CueClassification {
        // Sort once so the matching pass is deterministic.
        let wps = waypoints.sorted { $0.distanceFromStart < $1.distanceFromStart }
        let calcs = calculated.sorted { $0.distanceFromStart < $1.distanceFromStart }

        var consumedCalc = Set<Int>()  // calc.index values already paired with a waypoint
        var good: [CueEntry] = []
        var missing: [CueEntry] = []
        var extra: [CueEntry] = []
        var editBucket: [CueEntry] = []
        var unmatchedWaypoints: [TurnPoint] = []

        // Pass 1: distance + direction match.
        for wp in wps {
            let candidates = calcs.filter {
                !consumedCalc.contains($0.index) &&
                abs($0.distanceFromStart - wp.distanceFromStart) <= matchDistance &&
                directionsAgree(wp.direction, $0.direction)
            }
            let best = candidates.min {
                abs($0.distanceFromStart - wp.distanceFromStart) <
                abs($1.distanceFromStart - wp.distanceFromStart)
            }

            guard let id = wp.waypointID else {
                // Should never happen for waypoint-sourced TurnPoints; treat as Extra.
                extra.append(CueEntry(id: .detected(wp.index), kind: .extra, turn: wp))
                continue
            }

            if let match = best {
                consumedCalc.insert(match.index)
                if (wp.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                    missing.append(CueEntry(
                        id: .waypoint(id),
                        kind: .missingNameOnly,
                        turn: wp,
                        matchedCalculated: match
                    ))
                } else {
                    good.append(CueEntry(
                        id: .waypoint(id),
                        kind: .good,
                        turn: wp,
                        matchedCalculated: match
                    ))
                }
            } else {
                unmatchedWaypoints.append(wp)
            }
        }

        // Pass 2: unmatched waypoints — pair by distance only.
        for wp in unmatchedWaypoints {
            let candidates = calcs.filter {
                !consumedCalc.contains($0.index) &&
                abs($0.distanceFromStart - wp.distanceFromStart) <= matchDistance
            }
            let best = candidates.min {
                abs($0.distanceFromStart - wp.distanceFromStart) <
                abs($1.distanceFromStart - wp.distanceFromStart)
            }
            guard let id = wp.waypointID else { continue }  // wouldn't reach here

            if let match = best {
                consumedCalc.insert(match.index)
                // Roundabouts/rotaries/traffic-circles: the detector reads them
                // as a slight in/out turn that almost never matches the cue's
                // stated direction. Treat as Good rather than nagging the user.
                if isRoundaboutCue(wp) {
                    if (wp.description?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) {
                        missing.append(CueEntry(
                            id: .waypoint(id),
                            kind: .missingNameOnly,
                            turn: wp,
                            matchedCalculated: match
                        ))
                    } else {
                        good.append(CueEntry(
                            id: .waypoint(id),
                            kind: .good,
                            turn: wp,
                            matchedCalculated: match
                        ))
                    }
                } else {
                    editBucket.append(CueEntry(
                        id: .waypoint(id),
                        kind: .edit,
                        turn: wp,
                        matchedCalculated: match
                    ))
                }
            } else {
                // Genuinely solo waypoint — cue sheet says turn here, detector saw nothing.
                extra.append(CueEntry(id: .waypoint(id), kind: .extra, turn: wp))
            }
        }

        // Pass 3: any remaining calculated turns are pure Missing.
        for c in calcs where !consumedCalc.contains(c.index) {
            missing.append(CueEntry(id: .detected(c.index), kind: .missingDetected, turn: c))
        }

        let byDist: (CueEntry, CueEntry) -> Bool = {
            $0.turn.distanceFromStart < $1.turn.distanceFromStart
        }
        return CueClassification(
            missing: missing.sorted(by: byDist),
            extra: extra.sorted(by: byDist),
            edit: editBucket.sorted(by: byDist),
            good: good.sorted(by: byDist)
        )
    }

    /// True when the cue's text mentions a roundabout, traffic circle, or
    /// rotary — three regionally-equivalent names. Detectors typically read
    /// these as a single slight-left/right which won't match the cue's
    /// stated direction ("straight", "3rd exit", etc.).
    private static func isRoundaboutCue(_ wp: TurnPoint) -> Bool {
        let haystack = [
            wp.description ?? ""
        ].joined(separator: " ").lowercased()
        let keywords = ["roundabout", "traffic circle", "rotary"]
        return keywords.contains { haystack.contains($0) }
    }

    /// Directions agree if both turn the same way (left family vs right family vs
    /// u-turn vs straight). Sharp/slight modifiers don't disqualify a match.
    private static func directionsAgree(_ a: TurnDirection, _ b: TurnDirection) -> Bool {
        return side(a) == side(b)
    }

    private enum Side { case left, right, straight, uTurn }
    private static func side(_ d: TurnDirection) -> Side {
        switch d {
        case .sharpLeft, .left, .slightLeft:    return .left
        case .sharpRight, .right, .slightRight: return .right
        case .straight:                         return .straight
        case .uTurn:                            return .uTurn
        }
    }
}
