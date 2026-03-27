//
//  MetricType.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation

enum MetricType: String, Codable, CaseIterable, Identifiable {
    // Speed
    case speed
    case averageSpeed
    case maxSpeed

    // Distance
    case distance
    case distanceRemaining

    // Time
    case elapsedTime
    case movingTime

    // Heart rate
    case heartRate
    case averageHeartRate
    case maxHeartRate

    // Calories
    case calories

    // Elevation
    case currentElevation
    case elevationGain
    case elevationLoss
    case highestElevation
    case grade

    // Power
    case powerEstimate

    // Navigation
    case nextTurnDistance
    case nextTurnDirection
    case heading

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed: return "SPEED"
        case .averageSpeed: return "AVG SPEED"
        case .maxSpeed: return "MAX SPEED"
        case .distance: return "DISTANCE"
        case .distanceRemaining: return "REMAINING"
        case .elapsedTime: return "ELAPSED"
        case .movingTime: return "MOVING"
        case .heartRate: return "HR"
        case .averageHeartRate: return "AVG HR"
        case .maxHeartRate: return "MAX HR"
        case .calories: return "CAL"
        case .currentElevation: return "ELEVATION"
        case .elevationGain: return "ELEV GAIN"
        case .elevationLoss: return "ELEV LOSS"
        case .highestElevation: return "HIGH ELEV"
        case .grade: return "GRADE"
        case .powerEstimate: return "POWER"
        case .nextTurnDistance: return "NEXT TURN"
        case .nextTurnDirection: return "TURN DIR"
        case .heading: return "HEADING"
        }
    }

    /// Label that adapts based on activity type (pace vs speed)
    func displayLabel(for activity: ActivityType) -> String {
        switch self {
        case .speed: return activity.speedLabel
        case .averageSpeed: return activity.usesPace ? "AVG PACE" : "AVG SPEED"
        case .maxSpeed: return activity.usesPace ? "BEST PACE" : "MAX SPEED"
        default: return label
        }
    }

    var unit: String {
        switch self {
        case .speed, .averageSpeed, .maxSpeed: return currentUnits.speed.label
        case .distance, .distanceRemaining: return currentUnits.distance.label
        case .elapsedTime, .movingTime: return ""
        case .heartRate, .averageHeartRate, .maxHeartRate: return "bpm"
        case .calories: return "kcal"
        case .currentElevation, .elevationGain, .elevationLoss, .highestElevation: return currentUnits.elevation.label
        case .grade: return "%"
        case .powerEstimate: return "W"
        case .nextTurnDistance: return ""
        case .nextTurnDirection: return ""
        case .heading: return ""
        }
    }

    /// Unit that adapts based on activity type
    func displayUnit(for activity: ActivityType) -> String {
        switch self {
        case .speed, .averageSpeed, .maxSpeed:
            return activity.usesPace ? currentUnits.speed.paceLabel : currentUnits.speed.label
        default:
            return unit
        }
    }

    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .averageSpeed: return "gauge.with.dots.needle.33percent"
        case .maxSpeed: return "gauge.with.dots.needle.67percent"
        case .distance: return "point.topleft.down.to.point.bottomright.curvepath"
        case .distanceRemaining: return "flag.checkered"
        case .elapsedTime: return "clock"
        case .movingTime: return "clock.arrow.circlepath"
        case .heartRate: return "heart.fill"
        case .averageHeartRate: return "heart.text.clipboard"
        case .maxHeartRate: return "heart.bolt.fill"
        case .calories: return "flame.fill"
        case .currentElevation: return "mountain.2"
        case .elevationGain: return "arrow.up.right"
        case .elevationLoss: return "arrow.down.right"
        case .highestElevation: return "arrow.up.to.line"
        case .grade: return "angle"
        case .powerEstimate: return "bolt.fill"
        case .nextTurnDistance: return "arrow.turn.up.right"
        case .nextTurnDirection: return "arrow.triangle.turn.up.right.diamond"
        case .heading: return "location.north.fill"
        }
    }

    /// Whether this metric requires an active route to be meaningful
    var requiresRoute: Bool {
        switch self {
        case .distanceRemaining, .nextTurnDistance, .nextTurnDirection:
            return true
        default:
            return false
        }
    }

    /// Whether this metric is an estimate rather than a direct measurement
    var isEstimate: Bool {
        switch self {
        case .powerEstimate, .grade:
            return true
        default:
            return false
        }
    }
}
