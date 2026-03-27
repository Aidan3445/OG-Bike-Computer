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

    var body: some View {
        VStack(spacing: 6) {
            // Bearing arrow back to route
            Image(systemName: "arrow.up")
                .font(.system(size: 44, weight: .bold))
                .foregroundStyle(.red)
                .rotationEffect(.degrees(relativeArrowAngle))

            Text("OFF ROUTE")
                .font(.system(size: 16, weight: .heavy))
                .foregroundStyle(.red)

            Text(formatTurnDistance(workout.navigation.nearestRouteDistance))
                .font(.system(size: 22, weight: .bold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.red.opacity(0.8))

            if let missed = workout.navigation.missedTurn {
                Divider()
                HStack(spacing: 6) {
                    Image(systemName: missed.direction.icon)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.yellow)
                    Text("Missed \(missed.direction.label)")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.yellow)
                }
            }

            Spacer()

            HStack {
                MiniStat(label: "DIST", value: formatDistance(workout.totalDistance))
                Spacer()
                MiniStat(label: "TIME", value: formatTime(workout.movingTime))
            }
            .padding(.horizontal, 4)
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
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
