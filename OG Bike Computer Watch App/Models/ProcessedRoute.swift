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
}

struct TurnPoint {
    let index: Int
    let angle: Double
    let direction: TurnDirection
    let distanceFromStart: Double
    let coordinate: CLLocationCoordinate2D
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
    let turnPoints: [TurnPoint]
    let totalDistance: Double

    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double
}
