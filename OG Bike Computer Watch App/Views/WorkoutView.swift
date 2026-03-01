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

    @State private var voiceEnabled = true
    @State private var page = 2
    @State private var tab = 2

    var body: some View {
        TabView(selection: $page) {
            controlsOverlay
                .tag(1)

            TabView(selection: $tab) {
                navigationPage
                    .tag(1)

                RouteMapView(workout: workout)
                    .tag(2)

                metricsPage
                    .tag(3)
            }
            .tabViewStyle(.verticalPage)
            .scrollIndicators(.visible)
            .overlay(alignment: .topLeading) {
                if workout.isAutoPaused {
                    Text("AUTO-PAUSED")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.yellow)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.yellow.opacity(0.2))
                        .clipShape(Capsule())
                        .padding(.top, 20)
                        .padding(.leading, 12)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            .tag(2)
        }
        .tabViewStyle(.page)
    }

    private var navigationPage: some View {
        Group {
            if workout.navigation.isOffRoute {
                //OffRouteView(workout: workout)
            } else if workout.navigation.isRouteComplete {
                VStack(spacing: 8) {
                    Image(systemName: "flag.checkered")
                        .font(.system(size: 40))
                        .foregroundStyle(.green)
                    Text("Route Complete!")
                        .font(.headline)

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
            } else if let turn = workout.navigation.nextTurn {
                VStack(spacing: 4) {
                    Image(systemName: turn.direction.icon)
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(turnColor(workout.navigation.distanceToNextTurn))
                    Text(formatTurnDistance(workout.navigation.distanceToNextTurn))
                        .font(.system(size: 26, weight: .bold, design: .rounded))
                        .monospacedDigit()

                    Text(turn.direction.label)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)

                    Spacer()

                    HStack {
                        MiniStat(label: "DIST", value: formatDistance(workout.totalDistance))
                        Spacer()
                        MiniStat(label: "TIME", value: formatTime(workout.movingTime))
                        Spacer()
                        MiniStat(label: "TO END", value: formatDistance(workout.navigation.distanceRemaining))
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            } else {
                VStack(spacing: 4) {
                    Image(systemName: "arrow.up")
                        .font(.system(size: 44, weight: .bold))
                        .foregroundStyle(.green)
                    Text("On Route")
                        .font(.headline)

                    Spacer()

                    HStack {
                        MiniStat(label: "DIST", value: formatDistance(workout.totalDistance))
                        Spacer()
                        MiniStat(label: "TIME", value: formatTime(workout.movingTime))
                        Spacer()
                        MiniStat(label: "TO END", value: formatDistance(workout.navigation.distanceRemaining))
                    }
                    .padding(.horizontal, 4)
                }
                .padding(.horizontal, 8)
                .padding(.top, 8)
                .padding(.bottom, 4)
            }
        }
    }

    @Environment(\.isLuminanceReduced) var isLuminanceReduced
    private var metricsPage: some View {
        VStack(spacing: 4) {
            if workout.navigation.isOffRoute {
                //OffRouteBanner(workout: workout)
            }
            
            if isLuminanceReduced {
                MetricRow(
                    label: workout.currentActivity.speedLabel,
                    value: workout.currentActivity.usesPace
                    ? formatPace(workout.speed)
                    : formatSpeed(workout.speed),
                    unit: workout.currentActivity.usesPace ? "min/mi" : "mph")
                Divider()
                MetricRow(label: "DISTANCE", value: formatDistance(workout.totalDistance, false), unit: "mi")
                Divider()
                MetricRow(label: "TIME", value: formatTime(workout.elapsedTime), unit: "")
            } else {
                HStack {
                    MetricRow(
                        label: workout.currentActivity.speedLabel,
                        value: workout.currentActivity.usesPace
                        ? formatPace(workout.speed)
                        : formatSpeed(workout.speed),
                        unit: workout.currentActivity.usesPace ? "min/mi" : "mph")
                    
                    Spacer()
                    
                    MetricRow(label: "DISTANCE", value: formatDistance(workout.totalDistance, false), unit: "mi")
                }
                
                Divider()
                
                HStack {
                    MetricRow(label: "ELAPSED", value: formatTime(workout.elapsedTime), unit: "")
                    Spacer()
                    MetricRow(label: "MOVING", value: formatTime(workout.movingTime), unit: "")
                }
                
                Divider()
                
                HStack {
                    MetricRow(label: "HR", value: String(format: "%.0f", workout.heartRate), unit: "bpm")
                    Spacer()
                    MetricRow(label: "CAL", value: String(format: "%.0f", workout.activeCalories), unit: "kcal")
                }

                if let turn = workout.navigation.nextTurn {
                    Divider()
                    HStack(spacing: 6) {
                        Image(systemName: turn.direction.icon)
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(turnColor(workout.navigation.distanceToNextTurn))
                        Text("in \(formatTurnDistance(workout.navigation.distanceToNextTurn))")
                            .font(.system(size: 12, weight: .medium))
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(formatDistance(workout.navigation.distanceRemaining) + " to end")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }

    private var controlsOverlay: some View {
        ZStack(alignment: .topLeading) {
            Text(workout.isPaused || workout.isAutoPaused ? "Paused" : "Riding")
                .font(.headline)
                .foregroundStyle(workout.isAutoPaused || workout.isPaused ? .yellow : .green)
                .padding(.top, 20)
                .padding(.leading, 12)
                .ignoresSafeArea(edges: .top)
            
            VStack(spacing: 6) {
                if workout.isPaused || workout.isAutoPaused {
                    Button {
                        workout.resume()
                        withAnimation { page = 2 }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                } else {
                    Button {
                        workout.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.yellow)
                }
                Button(role: .destructive) {
                    onStop()
                } label: {
                    Label("End Ride", systemImage: "stop.fill")
                        .frame(maxWidth: .infinity)
                }
                
                Divider()
                
                Toggle(isOn: $voiceEnabled) {
                    Label("Voice", systemImage: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.caption)
                }
                .onChange(of: voiceEnabled) { _, newValue in
                    //VoiceNavigator.shared.isEnabled = newValue
                }
            }
            .padding()
            .scrollIndicators(.hidden)
        }
    }
}
