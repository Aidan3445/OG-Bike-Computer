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

    /// Convenience init preserving old call sites (calculated turns).
    init(index: Int, angle: Double, direction: TurnDirection, distanceFromStart: Double, coordinate: CLLocationCoordinate2D) {
        self.index = index
        self.angle = angle
        self.direction = direction
        self.distanceFromStart = distanceFromStart
        self.coordinate = coordinate
        self.description = nil
        self.isWaypoint = false
    }

    init(index: Int, angle: Double, direction: TurnDirection, distanceFromStart: Double, coordinate: CLLocationCoordinate2D, description: String?, isWaypoint: Bool) {
        self.index = index
        self.angle = angle
        self.direction = direction
        self.distanceFromStart = distanceFromStart
        self.coordinate = coordinate
        self.description = description
        self.isWaypoint = isWaypoint
    }
}

struct ProcessedPoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double?
    let distanceFromStart: Double
    let bearingToNext: Double
}

struct ProcessedRoute {
    let name: String
    let points: [ProcessedPoint]
    let waypointTurnPoints: [TurnPoint]
    let calculatedTurnPoints: [TurnPoint]
    let totalDistance: Double
    let hasWaypoints: Bool

    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    /// Returns the active turn list for a given mode.
    func turnPoints(for mode: TurnMode) -> [TurnPoint] {
        switch mode {
        case .provided:
            return waypointTurnPoints
        case .calculated:
            return calculatedTurnPoints
        case .both:
            return mergeTurns(waypoints: waypointTurnPoints, calculated: calculatedTurnPoints)
        }
    }

    /// Backward-compatible accessor — defaults to waypoints if available, else calculated.
    var turnPoints: [TurnPoint] {
        hasWaypoints ? waypointTurnPoints : calculatedTurnPoints
    }

    private func mergeTurns(waypoints: [TurnPoint], calculated: [TurnPoint]) -> [TurnPoint] {
        let suppressionRadius: Double = 100 // meters

        let filtered = calculated.filter { calc in
            !waypoints.contains { wpt in
                abs(wpt.distanceFromStart - calc.distanceFromStart) < suppressionRadius
            }
        }

        return (waypoints + filtered).sorted { $0.distanceFromStart < $1.distanceFromStart }
    }
}
