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
    @ObservedObject private var voice = VoiceNavigator.shared
    var onStop: () -> Void
    var extraTab: ExtraTab?

    @State private var page = 2
    @State private var tab = 1
    @State private var endCountdownStart: Date?
    @State private var endTimer: Timer?
    @State private var holdCountdownStart: Date?
    @State private var holdTimer: Timer?
    @State private var showNavOverlay = false
    @State private var navOverlayTask: Task<Void, Never>?
    @State private var showHoldExplainer = false
    @State private var holdExplainerDontShow = false

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
                let resolved = WorkoutTabOrder.resolve(
                    hasRoute: workout.hasRoute,
                    elevationEnabled: workout.ridePreferences.elevationScreen.enabled,
                    pages: metricConfig.config.pages,
                    stored: workout.ridePreferences.tabOrder
                )
                ForEach(Array(resolved.enumerated()), id: \.element.id) { index, key in
                    let tag = index + 1
                    switch key.kind {
                    case .routeMap:
                        RouteMapView(workout: workout)
                            .tag(tag)
                    case .elevation:
                        ElevationProfileView(workout: workout)
                            .tag(tag)
                    case .metricPage:
                        if let page = metricConfig.config.pages.first(where: { $0.id == key.metricPageID }) {
                            DynamicMetricsPage(
                                workout: workout,
                                metricPage: page,
                                showOffRouteBanner: !resolved.prefix(index).contains(where: { $0.kind == .metricPage })
                            )
                            .tag(tag)
                        }
                    }
                }
            }
            .tabViewStyle(.verticalPage)
            .scrollIndicators(.visible)
            .overlay(alignment: .topLeading) {
                if workout.isAutoPaused || workout.isPaused {
                    PausedPill(isAutoPaused: workout.isAutoPaused)
                        .padding(.top, 20)
                        .padding(.leading, 12)
                        .ignoresSafeArea(edges: .top)
                        .allowsHitTesting(false)
                }
            }
            // Nav turn overlay — flash stripped-down map when a turn is imminent and rider is on a non-map page
            .overlay {
                if showNavOverlay && tab > 1 && workout.ridePreferences.mapScreen.showTurnOverlay {
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
                guard newTurn != nil, tab > 1, workout.ridePreferences.mapScreen.showTurnOverlay else { return }
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
                guard dist > 0, dist < 150, tab > 1, !showNavOverlay, workout.ridePreferences.mapScreen.showTurnOverlay else { return }
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
                if newTab == 1 && showNavOverlay {
                    withAnimation(.easeOut(duration: 0.2)) { showNavOverlay = false }
                    navOverlayTask?.cancel()
                }
            }
            .onChange(of: workout.hasRoute) { hadRoute, hasRoute in
                    // Only auto-switch to the map on a fresh route load *before*
                    // the ride starts. Mid-ride route swaps may briefly toggle
                    // hasRoute false→true; jumping the rider's tab back to map
                    // during a ride is jarring, so we leave them where they are.
                    if hasRoute && !hadRoute && tab > 1 && !workout.isActive {
                        withAnimation { tab = 1 }
                    }
                }
            .onChange(of: metricConfig.config.pages.count) { _, _ in
                let resolvedCount = WorkoutTabOrder.resolve(
                    hasRoute: workout.hasRoute,
                    elevationEnabled: workout.ridePreferences.elevationScreen.enabled,
                    pages: metricConfig.config.pages,
                    stored: workout.ridePreferences.tabOrder
                ).count
                if tab > resolvedCount {
                    withAnimation { tab = max(resolvedCount, 1) }
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
            cancelEndCountdown()
            cancelHoldCountdown()
        }
        .sheet(isPresented: $showHoldExplainer) {
            holdExplainerSheet
        }
        // Another held ride already exists — let the rider decide what to do
        // with it before holding this one.
        .alert("Hold This Ride?", isPresented: $workout.pendingHoldConflict) {
            Button("Save & Hold") {
                workout.resolveHoldConflict(.saveAndHold)
            }
            Button("Discard & Hold", role: .destructive) {
                workout.resolveHoldConflict(.discardAndHold)
            }
            Button("Cancel", role: .cancel) {
                workout.resolveHoldConflict(.cancel)
            }
        } message: {
            Text("You already have a held ride. Save it (finish & keep) or discard it to put this ride on hold.")
        }
    }

    private var holdExplainerSheet: some View {
        ScrollView {
            VStack(spacing: 12) {
                Image(systemName: "hand.raised.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.orange)
                    .padding(.top, 8)

                Text("Hold Ride")
                    .font(.headline)

                Text("Your ride is paused and saved. You can resume it later from the route list — your distance, time, and route progress are preserved.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Divider()

                Toggle("Don't show again", isOn: $holdExplainerDontShow)
                    .font(.caption)

                Button("Got It") {
                    if holdExplainerDontShow {
                        UserDefaults.standard.set(true, forKey: "holdExplainerShown")
                    }
                    showHoldExplainer = false
                    workout.attemptHold()
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
            }
            .padding(.horizontal)
            .padding(.bottom, 16)
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
                        cancelCountdowns()
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
                        cancelCountdowns()
                        workout.pause()
                    } label: {
                        Image(systemName: "pause.fill")
                            .font(.title2)
                            .frame(width: 48, height: 48)
                            .background(.yellow, in: Circle())
                            .foregroundStyle(.white)
                    }
                    .buttonStyle(.plain)
                }

                ZStack {
                    if let start = holdCountdownStart {
                        Button { cancelCountdowns() } label: {
                            CountdownRing(start: start, duration: holdEndCountdownDuration, color: .orange)
                        }
                        .buttonStyle(.plain)
                    } else {
                        Button { startHoldCountdown() } label: {
                            Image(systemName: "hand.raised.fill")
                                .font(.title2)
                                .frame(width: 48, height: 48)
                                .background(Color.orange, in: Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                ZStack {
                    if let start = endCountdownStart {
                        Button { cancelCountdowns() } label: {
                            CountdownRing(start: start, duration: holdEndCountdownDuration, color: .red)
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

            Toggle(isOn: $voice.isEnabled) {
                Label("Voice", systemImage: voice.isEnabled ? "speaker.wave.2.fill" : "speaker.slash")
                    .font(.caption)
            }
            // Controls swallow the tap, so cancel alongside them.
            .simultaneousGesture(TapGesture().onEnded { cancelCountdowns() })

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
                .simultaneousGesture(TapGesture().onEnded { cancelCountdowns() })
            }

        }
        .ignoresSafeArea(edges: .top)
        .contentShape(Rectangle())
        .onTapGesture { cancelCountdowns() }
        .onChange(of: page) { _, _ in cancelCountdowns() }
    }

    /// Any tap on the controls page cancels whichever countdown is running.
    private func cancelCountdowns() {
        cancelEndCountdown()
        cancelHoldCountdown()
    }

    /// One timer that fires when the countdown ends, in the common run loop
    /// mode so scrolling doesn't hold it back. The ring reads the wall clock
    /// on its own, so a busy main thread can't slow the count down.
    private func countdownTimer(_ fire: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: holdEndCountdownDuration, repeats: false) { _ in
            guard workout.isActive, workout.completedRideSummary == nil else { return }
            fire()
        }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }

    private func startEndCountdown() {
        cancelCountdowns()
        endCountdownStart = Date()
        endTimer = countdownTimer {
            cancelEndCountdown()
            onStop()
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
        endCountdownStart = nil
    }

    private func startHoldCountdown() {
        cancelCountdowns()
        holdCountdownStart = Date()
        holdTimer = countdownTimer {
            cancelHoldCountdown()
            if UserDefaults.standard.bool(forKey: "holdExplainerShown") {
                workout.attemptHold()
            } else {
                holdExplainerDontShow = false
                showHoldExplainer = true
            }
        }
    }

    private func cancelHoldCountdown() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdCountdownStart = nil
    }
}

private let holdEndCountdownDuration: TimeInterval = 3

/// Ring and digit for the hold and end countdowns. Only this view redraws
/// while counting, and it reads the time on each frame, so it never runs slow.
private struct CountdownRing: View {
    let start: Date
    let duration: TimeInterval
    let color: Color

    var body: some View {
        TimelineView(.animation) { context in
            let elapsed = min(max(context.date.timeIntervalSince(start), 0), duration)
            ZStack {
                Circle()
                    .trim(from: 0, to: elapsed / duration)
                    .stroke(color, style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .frame(width: 48, height: 48)
                Text(String(max(1, Int(ceil(duration - elapsed)))))
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(color)
            }
        }
    }
}

#Preview("Countdown ring") {
    CountdownRing(start: Date(), duration: 3, color: .red)
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
                        .lineLimit(1)
                        .fixedSize()
                    Spacer()
                    Text(formatDistance(workout.navigation.distanceRemaining) + " to end")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .padding(.bottom, 4)
        .safeAreaPadding(.top)
    }
}

private struct PausedPill: View {
    let isAutoPaused: Bool

    var body: some View {
        Text(isAutoPaused ? "AUTO-PAUSED" : "PAUSED")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.yellow)
            .lineLimit(1)
            .fixedSize()
            .padding(.horizontal, 8)
            .padding(.vertical, 2)
            .background(.yellow.opacity(0.2))
            .clipShape(Capsule())
    }
}

// MARK: - Previews

#if DEBUG
extension WorkoutManager {
    /// Long auto-paused ride for layout previews, either off route after a
    /// missed turn or approaching the next one.
    static func preview(offRoute: Bool) -> WorkoutManager {
        let w = WorkoutManager()
        w.isActive = true
        w.elapsedTime = 40_357
        w.movingTime = 38_712
        w.totalDistance = 181_000
        w.speed = 9.8
        w.heartRate = 152
        w.autoPauseState = .paused
        let turn = TurnPoint(
            index: 0, angle: 30, direction: offRoute ? .slightLeft : .slightRight,
            distanceFromStart: 0, coordinate: .init(latitude: 0, longitude: 0))
        w.navigation.isOffRoute = offRoute
        w.navigation.nearestRouteDistance = 1_840
        w.navigation.missedTurn = offRoute ? turn : nil
        w.navigation.nextTurn = offRoute ? nil : turn
        w.navigation.distanceToNextTurn = 480
        w.navigation.distanceRemaining = 154_300
        return w
    }
}

private let previewMetricPage = MetricPage(name: "Ride", slots: [
    MetricSlot(type: .movingTime), MetricSlot(type: .elapsedTime),
    MetricSlot(type: .averageSpeed), MetricSlot(type: .distance),
    MetricSlot(type: .speed), MetricSlot(type: .heartRate),
])

#Preview("Metrics, 41 mm", traits: .fixedLayout(width: 176, height: 215)) {
    DynamicMetricsPage(workout: .preview(offRoute: false), metricPage: previewMetricPage, showOffRouteBanner: true)
}

#Preview("Metrics off route, 41 mm", traits: .fixedLayout(width: 176, height: 215)) {
    DynamicMetricsPage(workout: .preview(offRoute: true), metricPage: previewMetricPage, showOffRouteBanner: true)
}

#Preview("Paused pills", traits: .sizeThatFitsLayout) {
    VStack(spacing: 8) {
        PausedPill(isAutoPaused: true)
        PausedPill(isAutoPaused: false)
    }
    .padding()
    .frame(width: 176, alignment: .leading)
}
#endif
