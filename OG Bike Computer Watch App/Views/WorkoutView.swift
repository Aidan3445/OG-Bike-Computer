//
//  WorkoutView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI


struct WorkoutView: View {
    @ObservedObject var workout: WorkoutManager
    var onStop: () -> Void

    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    var body: some View {
        TabView {
            RouteMapView(workout: workout)
            navigationPage
            metricsPage
            controlsPage
        }
        .tabViewStyle(.verticalPage)
    }

    private var metricsPage: some View {
        VStack(spacing: 4) {
            if isLuminanceReduced {
                // Always-on display: show static snapshot, no live updates
                MetricRow(label: "SPEED", value: formatSpeed(workout.speed), unit: "mph")
                Divider()
                MetricRow(label: "DIST", value: formatDistance(workout.totalDistance), unit: "mi")
                Divider()
                MetricRow(label: "TIME", value: formatTime(workout.elapsedTime), unit: "")
            } else {
                HStack {
                    MetricRow(
                        label: "SPEED",
                        value: formatSpeed(workout.speed),
                        unit: "mph")
                    
                    Spacer()
                    
                    MetricRow(
                        label: "DISTANCE",
                        value: formatDistance(workout.totalDistance),
                        unit: "mi")
                }

                Divider()

                HStack {
                    MetricRow(
                        label: "MOVING",
                        value: formatTime(workout.movingTime),
                        unit: "")
                    
                    Spacer()
                    
                    MetricRow(
                        label: "TIME",
                        value: formatTime(workout.elapsedTime),
                        unit: "")
                }

                Divider()

                HStack {
                    MetricRow(
                        label: "HR",
                        value: String(format: "%.0f", workout.heartRate),
                        unit: "bpm")

                    Spacer()

                    MetricRow(
                        label: "CAL",
                        value: String(format: "%.0f", workout.activeCalories),
                        unit: "kcal")
                }
            }
            if workout.isAutoPaused {
                Text("AUTO-PAUSED")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 2)
                    .background(.yellow.opacity(0.2))
                    .clipShape(Capsule())
            }
        }
        .padding(.horizontal)
    }

    private var controlsPage: some View {
        VStack(spacing: 12) {
            if workout.isPaused {
                Button {
                    workout.resume()
                } label: {
                    Label("Resume", systemImage: "play.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.green)

                Button(role: .destructive) {
                        onStop()
                    } label: {
                        Label("End Ride", systemImage: "stop.fill")
                            .frame(maxWidth: .infinity)
                    }
            } else {
                Button {
                    workout.pause()
                } label: {
                    Label("Pause", systemImage: "pause.fill")
                        .frame(maxWidth: .infinity)
                }
                .tint(.yellow)
            }
        }
        .padding()
    }

    private var navigationPage: some View {
        VStack(spacing: 8) {
            if workout.navigation.isRouteComplete {
                Image(systemName: "flag.checkered")
                    .font(.system(size: 40))
                    .foregroundStyle(.green)
                Text("Route Complete!")
                    .font(.headline)
            } else if workout.navigation.isOffRoute {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 40))
                    .foregroundStyle(.red)
                Text("Off Route")
                    .font(.headline)
                    .foregroundStyle(.red)
            } else if let turn = workout.navigation.nextTurn {
                Image(systemName: turn.direction.icon)
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(turnColor)

                Text(formatTurnDistance(workout.navigation.distanceToNextTurn))
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .monospacedDigit()

                Text(turn.direction.label)
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Spacer()

                HStack {
                    Text("Remaining")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formatDistance(workout.navigation.distanceRemaining))
                        .font(.caption)
                        .bold()
                }
            } else {
                Image(systemName: "arrow.up")
                    .font(.system(size: 50, weight: .bold))
                    .foregroundStyle(.green)
                Text("On Route")
                    .font(.headline)
            }
        }
        .padding()
    }

    private var turnColor: Color {
        let dist = workout.navigation.distanceToNextTurn
        if dist < 50 { return .red }
        if dist < 200 { return .yellow }
        return .green
    }

    private func formatTurnDistance(_ meters: Double) -> String {
        if meters >= 1609 {
            return String(format: "%.1f mi", meters / 1609.34)
        } else if meters >= 160 {
            let feet = Int(meters * 3.28084)
            let rounded = (feet / 50) * 50
            return "\(rounded) ft"
        } else {
            let feet = Int(meters * 3.28084)
            return "\(feet) ft"
        }
    }
}
