//
//  ProcessedRoute.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

enum TurnDirection: String, Codable {
    case sharpLeft
    case left
    case slightLeft
    case straight
    case slightRight
    case right
    case sharpRight
    case uTurn

    var label: String {
        switch self {
        case .sharpLeft: return "Sharp Left"
        case .left: return "Left"
        case .slightLeft: return "Slight Left"
        case .straight: return "Straight"
        case .slightRight: return "Slight Right"
        case .right: return "Right"
        case .sharpRight: return "Sharp Right"
        case .uTurn: return "U-Turn"
        }
    }

    var icon: String {
        switch self {
        case .sharpLeft: return "arrow.turn.up.left"
        case .left: return "arrow.left"
        case .slightLeft: return "arrow.up.left"
        case .straight: return "arrow.up"
        case .slightRight: return "arrow.up.right"
        case .right: return "arrow.right"
        case .sharpRight: return "arrow.turn.up.right"
        case .uTurn: return "arrow.uturn.down"
        }
    }

    /// Returns true if the string contains a recognizable turn direction keyword.
    static func hasTurnKeyword(_ name: String) -> Bool {
        let lower = name.lowercased()
        let keywords = ["left", "right", "u-turn", "uturn", "straight", "keep", "sharp", "slight", "continue", "turn"]
        return keywords.contains { lower.contains($0) }
    }

    /// Map a GPX waypoint name (e.g. "Left", "Slight Right", "Uturn") to a TurnDirection.
    static func from(waypointName: String) -> TurnDirection {
        let lower = waypointName.lowercased().trimmingCharacters(in: .whitespaces)
        switch lower {
        case "left":                        return .left
        case "right":                       return .right
        case "slight left", "keep left":    return .slightLeft
        case "slight right", "keep right":  return .slightRight
        case "sharp left":                  return .sharpLeft
        case "sharp right":                 return .sharpRight
        case "uturn", "u-turn":             return .uTurn
        case "straight":                    return .straight
        default:
            if lower.contains("slight") && lower.contains("left") { return .slightLeft }
            if lower.contains("slight") && lower.contains("right") { return .slightRight }
            if lower.contains("sharp") && lower.contains("left") { return .sharpLeft }
            if lower.contains("sharp") && lower.contains("right") { return .sharpRight }
            if lower.contains("keep") && lower.contains("left") { return .slightLeft }
            if lower.contains("keep") && lower.contains("right") { return .slightRight }
            if lower.contains("left") { return .left }
            if lower.contains("right") { return .right }
            if lower.contains("u") && lower.contains("turn") { return .uTurn }
            return .straight
        }
    }
}

enum TurnMode: String, CaseIterable {
    case provided    // Waypoint turns only
    case calculated  // Algorithm turns only
    case both        // Waypoints primary, calculated fills gaps

    var label: String {
        switch self {
        case .provided:   return "Provided"
        case .calculated: return "Calculated"
        case .both:       return "Both"
        }
    }
}

struct TurnPoint {
    let index: Int
    let angle: Double
    let direction: TurnDirection
    let distanceFromStart: Double
    let coordinate: CLLocationCoordinate2D
    let description: String?  // e.g. "Turn right onto West School Street"
    let isWaypoint: Bool      // true if from GPX waypoint, false if calculated
    /// For waypoint-backed turns, the source Waypoint.id. Lets the Cue Editor
    /// resolve a TurnPoint back to its WaypointDecision. nil for calculated turns.
    let waypointID: UUID?

    /// Convenience init preserving old call sites (calculated turns).
    init(index: Int, angle: Double, direction: TurnDirection, distanceFromStart: Double, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.angle = angle
        self.direction = direction
        self.distanceFromStart = distanceFromStart
        self.coordinate = coordinate
        self.description = nil
        self.isWaypoint = false
        self.waypointID = nil
    }

    init(index: Int, angle: Double, direction: TurnDirection, distanceFromStart: Double, coordinate: CLLocationCoordinate2D, description: String?, isWaypoint: Bool, waypointID: UUID? = nil) {
        self.index = index
        self.angle = angle
        self.direction = direction
        self.distanceFromStart = distanceFromStart
        self.coordinate = coordinate
        self.description = description
        self.isWaypoint = isWaypoint
        self.waypointID = waypointID
    }
}

struct ProcessedPoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let distanceFromStart: Double
    let bearingToNext: Double
}

/// A POI mapped onto a processed route. `distanceFromStart` is the route distance
/// of the nearest route point; `offRouteDistance` is how far the POI sits from that
/// point (so we can decide whether it's on/near the route).
struct RoutePOI {
    let coordinate: CLLocationCoordinate2D
    let name: String
    let description: String?
    let distanceFromStart: Double
    let offRouteDistance: Double
    /// Index of the closest processed route point.
    let nearestPointIndex: Int
}

struct ProcessedRoute {
    let name: String
    let points: [ProcessedPoint]
    /// Raw waypoint cues from the GPX/import (pre-overlay). The Cue Editor reads
    /// this to classify Extra/Good; ride code should use `turnPoints(for:)`.
    let waypointTurnPoints: [TurnPoint]
    /// Raw detector output (pre-overlay). Same caveat as above.
    let calculatedTurnPoints: [TurnPoint]
    let pois: [RoutePOI]
    /// Simplified elevation series for cheap chart rendering (watch ElevationProfileView).
    let simplifiedElevation: [ElevationSample]
    let totalDistance: Double
    let hasWaypoints: Bool
    /// User-curated edits applied when computing `turnPoints(for:)`. nil = none.
    let cueEdits: CueEdits?

    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    init(name: String,
         points: [ProcessedPoint],
         waypointTurnPoints: [TurnPoint],
         calculatedTurnPoints: [TurnPoint],
         pois: [RoutePOI] = [],
         simplifiedElevation: [ElevationSample] = [],
         totalDistance: Double,
         hasWaypoints: Bool,
         cueEdits: CueEdits? = nil,
         minLat: Double, maxLat: Double, minLon: Double, maxLon: Double) {
        self.name = name
        self.points = points
        self.waypointTurnPoints = waypointTurnPoints
        self.calculatedTurnPoints = calculatedTurnPoints
        self.pois = pois
        self.simplifiedElevation = simplifiedElevation
        self.totalDistance = totalDistance
        self.hasWaypoints = hasWaypoints
        self.cueEdits = cueEdits
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    /// Returns the active turn list for a given mode, with the Cue Editor
    /// overlay applied where appropriate.
    ///
    /// - `.calculated` always ignores edits (raw detector output).
    /// - `.provided` applies edits to waypoints (drop skipped, override name/dir),
    ///   appends approved detector-only turns, and injects user-added cues.
    /// - `.both` does the same as `.provided`, then fills gaps with remaining
    ///   calculated turns (suppressing those within 100m of a kept cue).
    func turnPoints(for mode: TurnMode) -> [TurnPoint] {
        switch mode {
        case .calculated:
            return calculatedTurnPoints

        case .provided:
            let edited = applyEditsToWaypoints(waypointTurnPoints, edits: cueEdits)
            let approvedDetected = approvedDetectedTurns(edits: cueEdits)
            let added = addedCueTurns(edits: cueEdits)
            return (edited + approvedDetected + added)
                .sorted { $0.distanceFromStart < $1.distanceFromStart }

        case .both:
            let edited = applyEditsToWaypoints(waypointTurnPoints, edits: cueEdits)
            let approvedDetected = approvedDetectedTurns(edits: cueEdits)
            let added = addedCueTurns(edits: cueEdits)
            let primary = (edited + approvedDetected + added)
                .sorted { $0.distanceFromStart < $1.distanceFromStart }
            // Suppress raw calculated turns within 100m of anything we've kept.
            // Also drop any calculated turn the user explicitly dismissed.
            let dismissedIndices = Set(
                (cueEdits?.detectedDecisions ?? [:])
                    .filter { $0.value.status == .dismissed }
                    .map { $0.key }
            )
            let suppressionRadius: Double = 100
            let gapFill = calculatedTurnPoints.filter { calc in
                if dismissedIndices.contains(calc.index) { return false }
                // Already part of the primary list (approved detected)?
                if primary.contains(where: { $0.index == calc.index && !$0.isWaypoint }) {
                    return false
                }
                return !primary.contains { kept in
                    abs(kept.distanceFromStart - calc.distanceFromStart) < suppressionRadius
                }
            }
            return (primary + gapFill).sorted { $0.distanceFromStart < $1.distanceFromStart }
        }
    }

    /// Backward-compatible accessor — defaults to waypoints if available, else calculated.
    var turnPoints: [TurnPoint] {
        hasWaypoints ? waypointTurnPoints : calculatedTurnPoints
    }

    /// Apply the overlay to the raw waypoint cues: drop skipped, apply name and
    /// direction overrides. The description is resolved as:
    ///     fullCueOverride > substitute(streetName, into: original) > original.
    /// Unedited waypoints pass through unchanged.
    private func applyEditsToWaypoints(_ waypoints: [TurnPoint], edits: CueEdits?) -> [TurnPoint] {
        guard let edits = edits else { return waypoints }
        return waypoints.compactMap { tp -> TurnPoint? in
            guard let wid = tp.waypointID, let decision = edits.waypointDecisions[wid] else {
                return tp
            }
            if decision.status == .skipped { return nil }
            let newDirection = decision.directionOverride ?? tp.direction
            let newDescription: String?
            if let custom = decision.fullCueOverride, !custom.isEmpty {
                newDescription = custom
            } else if let name = decision.nameOverride, !name.isEmpty {
                if let original = tp.description, !original.isEmpty {
                    newDescription = CueTextParser.substitute(in: original, with: name)
                } else {
                    newDescription = CueTextParser.compose(direction: newDirection, streetName: name)
                }
            } else {
                newDescription = tp.description
            }
            return TurnPoint(
                index: tp.index,
                angle: tp.angle,
                direction: newDirection,
                distanceFromStart: tp.distanceFromStart,
                coordinate: tp.coordinate,
                description: newDescription.map(RoadNameExpander.expand),
                isWaypoint: true,
                waypointID: tp.waypointID
            )
        }
    }

    /// Materialize detector-only turns the user has approved into TurnPoints.
    /// Description is resolved as fullCueOverride > composed("<verb> onto <name>") > nil.
    private func approvedDetectedTurns(edits: CueEdits?) -> [TurnPoint] {
        guard let edits = edits else { return [] }
        let calcByIndex = Dictionary(uniqueKeysWithValues: calculatedTurnPoints.map { ($0.index, $0) })
        return edits.detectedDecisions.compactMap { (index, decision) -> TurnPoint? in
            guard decision.status == .approved, let base = calcByIndex[index] else { return nil }
            let direction = decision.direction ?? base.direction
            let desc: String?
            if let custom = decision.fullCueOverride, !custom.isEmpty {
                desc = custom
            } else if let name = decision.name, !name.isEmpty {
                desc = CueTextParser.compose(direction: direction, streetName: name)
            } else {
                desc = nil
            }
            return TurnPoint(
                index: base.index,
                angle: base.angle,
                direction: direction,
                distanceFromStart: base.distanceFromStart,
                coordinate: base.coordinate,
                description: desc.map(RoadNameExpander.expand),
                isWaypoint: false,
                waypointID: nil
            )
        }
    }

    /// Materialize user-added cues into TurnPoints, anchoring them to the
    /// track-point at the cue's recorded index. Out-of-range indices are
    /// dropped (e.g. after a route re-import that shifted the track).
    private func addedCueTurns(edits: CueEdits?) -> [TurnPoint] {
        guard let edits = edits, !edits.addedCues.isEmpty else { return [] }
        return edits.addedCues.compactMap { cue -> TurnPoint? in
            guard cue.trackPointIndex >= 0, cue.trackPointIndex < points.count else { return nil }
            let pt = points[cue.trackPointIndex]
            let desc: String?
            if let custom = cue.fullCueOverride, !custom.isEmpty {
                desc = custom
            } else if !cue.name.isEmpty {
                desc = CueTextParser.compose(direction: cue.direction, streetName: cue.name)
            } else {
                desc = nil
            }
            return TurnPoint(
                index: cue.trackPointIndex,
                angle: 0,
                direction: cue.direction,
                distanceFromStart: pt.distanceFromStart,
                coordinate: pt.coordinate,
                description: desc.map(RoadNameExpander.expand),
                isWaypoint: false,
                waypointID: nil
            )
        }
    }

    /// POIs resolved against the overlay: imported POIs get title/coord
    /// overrides applied and skipped ones removed; user-added POIs are
    /// appended. The result is what the ride view (and any future watch UI)
    /// should display. Imported POIs without a matching backing Waypoint id
    /// (legacy data) pass through unchanged.
    func resolvedPOIs(importedWaypoints: [Waypoint]) -> [RoutePOI] {
        // Build an id → imported Waypoint lookup so we can resolve overrides
        // back to a coordinate when the user has relocated the POI.
        let importedByID = Dictionary(uniqueKeysWithValues: importedWaypoints.pois.map { ($0.id, $0) })
        let edits = cueEdits
        let kept: [RoutePOI] = pois.compactMap { poi -> RoutePOI? in
            // Find the underlying Waypoint by coordinate match (RoutePOI doesn't
            // carry the id directly). Pois generated from imports came from
            // exactly those Waypoints, so coordinate equality is safe enough.
            let wp = importedByID.values.first { $0.lat == poi.coordinate.latitude && $0.lon == poi.coordinate.longitude && $0.name == poi.name }
            guard let wp = wp, let decision = edits?.poiDecisions[wp.id] else {
                return poi
            }
            if decision.status == .skipped { return nil }
            let newName = decision.titleOverride ?? poi.name
            let newCoord: CLLocationCoordinate2D
            if let lat = decision.latitudeOverride, let lon = decision.longitudeOverride {
                newCoord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
            } else {
                newCoord = poi.coordinate
            }
            return RoutePOI(
                coordinate: newCoord,
                name: newName,
                description: poi.description,
                distanceFromStart: poi.distanceFromStart,
                offRouteDistance: poi.offRouteDistance,
                nearestPointIndex: poi.nearestPointIndex
            )
        }
        let added: [RoutePOI] = (edits?.addedPOIs ?? []).map { added in
            RoutePOI(
                coordinate: CLLocationCoordinate2D(latitude: added.lat, longitude: added.lon),
                name: added.name,
                description: nil,
                distanceFromStart: 0,
                offRouteDistance: 0,
                nearestPointIndex: 0
            )
        }
        return kept + added
    }
}
