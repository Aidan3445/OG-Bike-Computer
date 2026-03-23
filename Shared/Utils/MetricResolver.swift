//
//  MetricResolver.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation

#if os(watchOS)
/// Resolves a MetricType into display strings using live WorkoutManager data.
struct MetricResolver {
    let workout: WorkoutManager

    struct Resolved {
        let label: String
        let value: String
        let unit: String
    }

    func resolve(_ type: MetricType) -> Resolved {
        let activity = workout.currentActivity
        let label = type.displayLabel(for: activity)
        let unit = type.displayUnit(for: activity)

        let value: String
        switch type {
        case .speed:
            value = activity.usesPace
                ? formatPace(workout.speed)
                : formatSpeed(workout.speed, false)

        case .averageSpeed:
            value = activity.usesPace
                ? formatPace(workout.averageSpeed)
                : formatSpeed(workout.averageSpeed, false)

        case .maxSpeed:
            value = activity.usesPace
                ? formatPace(workout.maxSpeed)
                : formatSpeed(workout.maxSpeed, false)

        case .distance:
            value = formatDistance(workout.totalDistance, false)

        case .distanceRemaining:
            value = formatDistance(workout.navigation.distanceRemaining, false)

        case .elapsedTime:
            value = formatTime(workout.elapsedTime)

        case .movingTime:
            value = formatTime(workout.movingTime)

        case .heartRate:
            value = formatHeartRate(workout.heartRate)

        case .averageHeartRate:
            value = formatHeartRate(workout.averageHeartRate)

        case .maxHeartRate:
            value = formatHeartRate(workout.maxHeartRate)

        case .calories:
            value = String(format: "%.0f", workout.activeCalories)

        case .currentElevation:
            value = formatElevationValue(workout.currentElevation)

        case .elevationGain:
            value = formatElevationValue(workout.liveElevationGain)

        case .elevationLoss:
            value = formatElevationValue(workout.liveElevationLoss)

        case .highestElevation:
            let elev = workout.highestElevation
            value = elev > -1_000_000 ? formatElevationValue(elev) : "--"

        case .grade:
            value = formatGrade(workout.currentGrade)

        case .powerEstimate:
            value = formatPower(workout.estimatedPower)

        case .nextTurnDistance:
            if let _ = workout.navigation.nextTurn {
                value = formatTurnDistance(workout.navigation.distanceToNextTurn)
            } else {
                value = "--"
            }

        case .nextTurnDirection:
            if let turn = workout.navigation.nextTurn {
                value = turn.direction.label
            } else {
                value = "--"
            }

        case .heading:
            value = formatHeading(workout.heading)
        }

        return Resolved(label: label, value: value, unit: unit)
    }
}
#endif
