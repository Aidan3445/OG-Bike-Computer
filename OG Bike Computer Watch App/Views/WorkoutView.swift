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
    @ObservedObject private var unitState = UnitState.shared
    var onStop: () -> Void
    var extraTab: ExtraTab?

    @State private var voiceEnabled = true
    @State private var page = 2
    @State private var tab = 1
    @State private var endCountdown: Double = 0
    @State private var endTimer: Timer?
    @State private var showNavOverlay = false
    @State private var navOverlayTask: Task<Void, Never>?

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
        let _ = unitState.preferences
        TabView(selection: $page) {
            controlsOverlay
                .tag(1)

            TabView(selection: $tab) {
                RouteMapView(workout: workout)
                    .tag(1)

                // Dynamic metric pages from config
                ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, metricPage in
                    DynamicMetricsPage(
                        workout: workout,
                        metricPage: metricPage,
                        showOffRouteBanner: index == 0
                    )
                    .tag(2 + index)
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
            // Nav turn overlay — flash stripped-down map when a turn is imminent and rider is on a metrics page
            .overlay {
                if showNavOverlay && tab >= 3 && workout.ridePreferences.mapScreen.showTurnOverlay {
                    ZStack {
                        Color.black.opacity(0.85)
                        RouteMapView(workout: workout, isOverlay: true)
                    }
                    .transition(.opacity)
                    .allowsHitTesting(true)
                    .onTapGesture {
                        withAnimation(.easeOut(duration: 0.25)) { showNavOverlay = false }
                    }
                }
            }
            .onChange(of: workout.navigation.nextTurn?.index) { oldTurn, newTurn in
                // A new turn became the next turn (rider passed one or a new one appeared)
                guard newTurn != nil, tab >= 3, workout.ridePreferences.mapScreen.showTurnOverlay else { return }
                navOverlayTask?.cancel()
                withAnimation(.easeIn(duration: 0.2)) { showNavOverlay = true }
                navOverlayTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) { showNavOverlay = false }
                    }
                }
            }
            .onChange(of: workout.navigation.distanceToNextTurn) { _, dist in
                // Also flash when approaching a turn closely
                guard dist > 0, dist < 150, tab >= 3, !showNavOverlay, workout.ridePreferences.mapScreen.showTurnOverlay else { return }
                navOverlayTask?.cancel()
                withAnimation(.easeIn(duration: 0.2)) { showNavOverlay = true }
                navOverlayTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        withAnimation(.easeOut(duration: 0.3)) { showNavOverlay = false }
                    }
                }
            }
            .onChange(of: tab) { _, newTab in
                // Dismiss overlay when user swipes to map themselves
                if newTab <= 2 && showNavOverlay {
                    withAnimation(.easeOut(duration: 0.2)) { showNavOverlay = false }
                    navOverlayTask?.cancel()
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
            .onChange(of: metricConfig.config.pages.count) { _, count in
                // Clamp tab to valid range when pages are added/removed
                let maxTab = 2 + count
                if tab > maxTab {
                    withAnimation { tab = max(maxTab, 1) }
                }
            }
            .tag(2)

            if let extraTab {
                extraTab
                    .tag(3)
            }
        }
        .tabViewStyle(.page)
        .onDisappear {
            navOverlayTask?.cancel()
            navOverlayTask = nil
            showNavOverlay = false
        }
    }

    private var controlsOverlay: some View {
        VStack(spacing: 8) {
            Text(workout.isPaused || workout.isAutoPaused ? "Paused" : "Riding")
                .font(.headline)
                .foregroundStyle(workout.isAutoPaused || workout.isPaused ? .yellow : .green)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            HStack(spacing: 10) {
                if workout.isPaused || workout.isAutoPaused {
                    Button {
                        cancelEndCountdown()
                        workout.resume()
                        withAnimation { page = 2 }
                    } label: {
                        Image(systemName: "play.fill")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color.green, in: Circle())
                    }
                    .buttonStyle(.plain)
                } else {
                    Button {
                        cancelEndCountdown()
                        workout.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(Color.yellow, in: Circle())
                            .foregroundStyle(.black)
                    }
                    .buttonStyle(.plain)
                }

                Button {
                    cancelEndCountdown()
                    workout.holdRide()
                } label: {
                    Image(systemName: "hand.raised.fill")
                        .font(.title2)
                        .frame(width: 48, height: 48)
                        .background(Color.orange, in: Circle())
                }
                .buttonStyle(.plain)

                ZStack {
                    if endCountdown > 0 {
                        Button { cancelEndCountdown() } label: {
                            ZStack {
                                Circle()
                                    .trim(from: 0, to: endCountdown / 3.0)
                                    .stroke(.red, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                                    .rotationEffect(.degrees(-90))
                                    .frame(width: 48, height: 48)
                                Text(String(Int(ceil(3.0 - endCountdown))))
                                    .font(.system(size: 18, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                    .foregroundStyle(.red)
                            }
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { startEndCountdown() } label: {
                            Image(systemName: "stop.fill")
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(Color.red, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            Divider()

            Toggle(isOn: $voiceEnabled) {
                Label("Voice", systemImage: voiceEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.caption)
            }
            .onChange(of: voiceEnabled) { _, newValue in
                VoiceNavigator.shared.isEnabled = newValue
            }

            if workout.navigation.processedRoute?.hasWaypoints == true {
                Divider()
                HStack {
                    Label("Turns", systemImage: "arrow.triangle.turn.up.right.diamond")
                        .font(.caption)
                    Spacer()
                    HStack(spacing: 4) {
                        ForEach([TurnMode.provided, .calculated, .both], id: \.self) { mode in
                            Button {
                                workout.navigation.setTurnMode(mode)
                            } label: {
                                Text(turnModeShortLabel(mode))
                                    .font(.system(size: 11, weight: workout.navigation.turnMode == mode ? .bold : .regular))
                                    .foregroundStyle(workout.navigation.turnMode == mode ? .white : .secondary)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 3)
                                    .background(
                                        workout.navigation.turnMode == mode
                                            ? Color.white.opacity(0.2)
                                            : Color.clear
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
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

    private func turnModeShortLabel(_ mode: TurnMode) -> String {
        switch mode {
        case .provided:   return "Cues"
        case .calculated: return "Calc"
        case .both:       return "Both"
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
