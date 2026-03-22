//
//  WorkoutView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct WorkoutView<ExtraTab: View>: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject var metricConfig: MetricConfigStore
    var onStop: () -> Void
    var extraTab: ExtraTab?

    @State private var voiceEnabled = true
    @State private var page = 2
    @State private var tab = 2
    @State private var endCountdown: Double = 0
    @State private var endTimer: Timer?

    init(workout: WorkoutManager, metricConfig: MetricConfigStore, onStop: @escaping () -> Void) where ExtraTab == EmptyView {
        self.workout = workout
        self.metricConfig = metricConfig
        self.onStop = onStop
        self.extraTab = nil
    }

    init(workout: WorkoutManager, metricConfig: MetricConfigStore, onStop: @escaping () -> Void, @ViewBuilder extraTab: () -> ExtraTab) {
        self.workout = workout
        self.metricConfig = metricConfig
        self.onStop = onStop
        self.extraTab = extraTab()
    }

    var body: some View {
        TabView(selection: $page) {
            controlsOverlay
                .tag(1)

            TabView(selection: $tab) {
                navigationPage
                    .tag(1)

                RouteMapView(workout: workout)
                    .tag(2)

                // Dynamic metric pages from config
                ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, metricPage in
                    DynamicMetricsPage(
                        workout: workout,
                        metricPage: metricPage,
                        showOffRouteBanner: index == 0
                    )
                    .tag(3 + index)
                }
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
            .overlay(alignment: .bottom) {
                if workout.navigation.showReversePrompt {
                    VStack(spacing: 6) {
                        Text("Heading back?")
                            .font(.system(size: 13, weight: .bold))
                        Text("Reverse remaining route?")
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                        HStack(spacing: 12) {
                            Button {
                                workout.navigation.reverseRemainingRoute()
                            } label: {
                                Text("Reverse")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(.blue)

                            Button {
                                workout.navigation.dismissReversePrompt()
                            } label: {
                                Text("Dismiss")
                                    .font(.system(size: 12, weight: .semibold))
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(.gray)
                        }
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 8)
                    .padding(.bottom, 4)
                }
            }
            .onChange(of: workout.hasRoute) { _, hasRoute in
                    if hasRoute && tab >= 3 {
                        // Loaded a route mid-ride — switch to map
                        withAnimation { tab = 2 }
                    } else if !hasRoute {
                        // Cleared route — go to first metrics page
                        withAnimation { tab = 3 }
                    }
                }
            .tag(2)

            if let extraTab {
                extraTab
                    .tag(3)
            }
        }
        .tabViewStyle(.page)
    }

    private var navigationPage: some View {
        Group {
            if workout.navigation.isOffRoute {
                OffRouteView(workout: workout)
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

    private var controlsOverlay: some View {
        VStack(spacing: 12) {
            Text(workout.isPaused || workout.isAutoPaused ? "Paused" : "Riding")
                .font(.headline)
                .foregroundStyle(workout.isAutoPaused || workout.isPaused ? .yellow : .green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top,16)
                if workout.isPaused || workout.isAutoPaused {
                    Button {
                        cancelEndCountdown()
                        workout.resume()
                        withAnimation { page = 2 }
                    } label: {
                        Label("Resume", systemImage: "play.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.green)
                } else {
                    Button {
                        cancelEndCountdown()
                        workout.pause()
                    } label: {
                        Label("Pause", systemImage: "pause.fill")
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.yellow)
                }
                ZStack {
                    if endCountdown > 0 {
                        Button { cancelEndCountdown() } label: {
                            ZStack {
                                Circle()
                                    .trim(from: 0, to: endCountdown / 3.0)
                                    .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 36, height: 36)
                                Text(String(Int(ceil(3.0 - endCountdown))))
                                    .font(.system(size: 16, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button(role: .destructive) { startEndCountdown() } label: {
                            Label("End Ride", systemImage: "stop.fill")
                                .frame(maxWidth: .infinity)
                        }
                    }
                }
                .frame(height: 44)
                Divider()
                Toggle(isOn: $voiceEnabled) {
                    Label("Voice", systemImage: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                        .font(.caption)
                }
                .onChange(of: voiceEnabled) { _, newValue in
                    VoiceNavigator.shared.isEnabled = newValue
                }
            
        }
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .onTapGesture {
            if endCountdown > 0 { cancelEndCountdown() }
        }
        .onChange(of: page) { _, _ in cancelEndCountdown() }
    }

    private func startEndCountdown() {
        endCountdown = 0.001 // trigger visible state
        endTimer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { _ in
            endCountdown += 0.05
            if endCountdown >= 3.0 {
                cancelEndCountdown()
                onStop()
            }
        }
    }

    private func cancelEndCountdown() {
        endTimer?.invalidate()
        endTimer = nil
        endCountdown = 0
    }
}

// MARK: - Dynamic Metrics Page

struct DynamicMetricsPage: View {
    @ObservedObject var workout: WorkoutManager
    let metricPage: MetricPage
    let showOffRouteBanner: Bool

    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    var body: some View {
        let resolver = MetricResolver(workout: workout)
        let slots = metricPage.slots
        let rows = slots.chunked(into: isLuminanceReduced ? 1 : 2)

        VStack(spacing: 4) {
            if showOffRouteBanner && workout.navigation.isOffRoute {
                OffRouteBanner(workout: workout)
            }

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if rowIdx > 0 { Divider() }

                if row.count == 1 {
                    let resolved = resolver.resolve(row[0].type)
                    MetricRow(label: resolved.label, value: resolved.value, unit: resolved.unit, alignment: .center)
                } else {
                    HStack {
                        let r0 = resolver.resolve(row[0].type)
                        MetricRow(label: r0.label, value: r0.value, unit: r0.unit, alignment: .leading)
                        Spacer()
                        let r1 = resolver.resolve(row[1].type)
                        MetricRow(label: r1.label, value: r1.value, unit: r1.unit, alignment: .trailing)
                    }
                }
            }

            // Show next turn info at bottom of first metrics page if on route
            if showOffRouteBanner, let turn = workout.navigation.nextTurn, !isLuminanceReduced {
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
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
    }
}
