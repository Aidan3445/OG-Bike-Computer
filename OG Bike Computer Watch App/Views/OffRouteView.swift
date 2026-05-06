//
//  OffRouteView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//

import SwiftUI

struct OffRouteView: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared

    private var mapConfig: MapScreenConfig { workout.ridePreferences.mapScreen }

    var body: some View {
        let _ = unitState.preferences
        VStack(spacing: 4) {
            // Bearing arrow back to route
            Image(systemName: "arrow.up")
                .font(.system(size: 36, weight: .bold))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(relativeArrowAngle))

            Text("OFF ROUTE")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(.red)

            Text(formatTurnDistance(workout.navigation.nearestRouteDistance))
                .font(.system(size: 18, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red.opacity(0.8))

            if let missed = workout.navigation.missedTurn {
                HStack(spacing: 6) {
                    Image(systemName: missed.direction.icon)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text("Missed \(missed.direction.label)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.yellow)
                }
            }

            Divider().padding(.vertical, 2)

            // Map-screen stats so the rider doesn't lose stat visibility while off route.
            mapScreenStats

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    @ViewBuilder
    private var mapScreenStats: some View {
        VStack(spacing: 1) {
            if mapConfig.primaryStat != .none {
                let primary = resolveStat(mapConfig.primaryStat)
                HStack(spacing: 2) {
                    Text(primary.value)
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    if let unit = primary.unit {
                        Text(unit)
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
                }
            }

            ForEach(Array(mapConfig.secondaryStats.enumerated()), id: \.offset) { index, stat in
                if stat != .none {
                    let resolved = resolveStat(stat)
                    let display = resolved.unit != nil ? "\(resolved.value) \(resolved.unit!)" : resolved.value
                    Text(display)
                        .font(.system(size: index == mapConfig.secondaryStats.count - 1 ? 9 : 11,
                                      weight: .semibold, design: .rounded))
                        .foregroundStyle(index == mapConfig.secondaryStats.count - 1 ? .secondary : .primary)
                }
            }
        }
    }

    private func resolveStat(_ type: MapStatType) -> (value: String, unit: String?) {
        switch type {
        case .speed:
            return (formatSpeed(workout.speed, false), currentUnits.speed.label)
        case .averageSpeed:
            return (formatSpeed(workout.averageSpeed, false), currentUnits.speed.label)
        case .heartRate:
            return (workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "--", "bpm")
        case .distance:
            return (formatDistance(workout.totalDistance), nil)
        case .movingTime:
            return (formatTime(workout.movingTime), nil)
        case .elapsedTime:
            return (formatTime(workout.elapsedTime), nil)
        case .elevation:
            return (formatElevation(workout.currentElevation), nil)
        case .grade:
            return (String(format: "%.1f%%", workout.currentGrade), nil)
        case .power:
            return (workout.estimatedPower > 0 ? "\(Int(workout.estimatedPower))" : "--", "W")
        case .distanceRemaining:
            return (formatDistance(workout.navigation.distanceRemaining), nil)
        case .calories:
            return ("\(Int(workout.activeCalories))", "cal")
        case .none:
            return ("", nil)
        }
    }

    // Rotate arrow to point toward the route relative to current heading
    private var relativeArrowAngle: Double {
        let bearing = workout.navigation.bearingToRoute
        let heading: Double
        if workout.speed > 1.0, let course = workout.currentLocation?.course, course >= 0 {
            heading = course
        } else {
            heading = workout.heading
        }
        return bearing - heading
    }
}

struct OffRouteBanner: View {
    @ObservedObject var workout: WorkoutManager

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.red)
            Text("OFF ROUTE")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(.red)
            Text("• \(formatTurnDistance(workout.navigation.nearestRouteDistance))")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.red.opacity(0.7))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(.red.opacity(0.15))
        .clipShape(Capsule())
    }
}
