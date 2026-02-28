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

    var body: some View {
        TabView {
            metricsPage
            controlsPage
        }
        .tabViewStyle(.verticalPage)
    }

    private var metricsPage: some View {
        VStack(spacing: 6) {
            MetricRow(
                label: "SPEED",
                value: formatSpeed(workout.speed),
                unit: "mph")

            Divider()

            MetricRow(
                label: "DISTANCE",
                value: formatDistance(workout.totalDistance),
                unit: "mi")

            Divider()

            MetricRow(
                label: "TIME",
                value: formatTime(workout.elapsedTime),
                unit: "")

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
}
