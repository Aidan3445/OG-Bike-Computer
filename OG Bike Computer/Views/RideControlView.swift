//
//  RideControlView.swift
//  OG Bike Computer
//
//  Full ride control screen accessible from the Live Activity deep link
//  and the dynamic "Ride" tab during an active workout. Shows live stats
//  in a swipeable carousel matching the watch's metric pages, plus controls
//  for pause/resume, end ride, voice toggle, and route changes.
//

#if os(iOS)
import SwiftUI

struct RideControlView: View {
    @ObservedObject private var telemetry = PhoneTelemetryStore.shared
    @ObservedObject private var session = RideSessionManager.shared
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var routeStore: RouteStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject private var unitState = UnitState.shared
    @ObservedObject private var connectivity = ConnectivityManager.shared

    @State private var showEndConfirmation = false
    @State private var showDiscardAlert = false
    @State private var showSettingsRevertPrompt = false
    @State private var showRoutePicker = false
    @State private var showHoldConfirmation = false
    @State private var showHoldConflictAlert = false
    @State private var showRouteDetail = false
    @State private var activeRoute: Route?
    @State private var selectedPage = 0
    /// Rolling (movingTime, totalDistance) samples used to derive a recent
    /// split average speed for the ETA estimate. Trimmed to the last ~180s
    /// of moving time on each telemetry update.
    @State private var recentSpeedSamples: [(movingTime: TimeInterval, distance: Double)] = []

    /// Pending state is sourced from `session.pendingCommand` so it survives
    /// view rebuilds and stays consistent with Live Activity / widget intents
    /// that might issue commands while this view is open.
    private var isPausing: Bool { session.pendingCommand == .pause }
    private var isResuming: Bool { session.pendingCommand == .resume }
    private var isHolding: Bool { session.pendingCommand == .hold }
    private var isEnding: Bool {
        session.pendingCommand == .end || session.pendingCommand == .discard
    }
    private var pauseResumeBusy: Bool { isPausing || isResuming }
    private var controlsBusy: Bool { isHolding || isEnding }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            // Navigation alert bar
            navigationBar
                .padding(.horizontal)
                .padding(.top, 8)

            // Metric pages carousel
            TabView(selection: $selectedPage) {
                ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, page in
                    MetricPageView(page: page, telemetry: telemetry)
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .automatic))
            .frame(maxHeight: .infinity)

            // Controls
            controlBar
                .padding(.horizontal)
                .padding(.bottom, 16)
        }
        .onChange(of: session.isRideActive, initial: false) { isActive, _  in
            if !isActive {
                dismiss()
            }
        }
        // Sync active route whenever the watch reports a different route ID
        .onChange(of: telemetry.activeRouteID, initial: true) { _, newID in
            activeRoute = newID.flatMap { id in routeStore.routes.first { $0.id == id } }
        }
        .onChange(of: telemetry.totalDistance, initial: false) { _, _ in
            updateRecentSpeedSamples()
        }
        .background(telemetry.isOffRoute ? Color(red: 0.12, green: 0.02, blue: 0.02) : Color(.systemGroupedBackground))
        .navigationTitle(session.isPaused ? "Paused" : "Riding")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Discard Ride?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                // Optimistic discard — dismisses the screen immediately, sends
                // the command to the watch in the background.
                session.optimisticDiscard()
                userSettings.clearRideTracking()
            }
            Button("Save Anyway") {
                session.optimisticEnd()
                checkSettingsRevert()
            }
        } message: {
            Text("This ride is under 1 minute. Do you want to save it anyway?")
        }
        .alert("End Ride?", isPresented: $showEndConfirmation) {
            Button("End & Save", role: .destructive) {
                session.optimisticEnd()
                checkSettingsRevert()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will end the current ride and save it.")
        }
        .alert("Settings Changed During Ride", isPresented: $showSettingsRevertPrompt) {
            Button("Keep Changes") {
                userSettings.clearRideTracking()
            }
            Button("Update \(userSettings.activeProfileName)") {
                userSettings.clearRideTracking()
            }
            Button("Revert to Original", role: .destructive) {
                userSettings.revertRideChanges()
            }
        } message: {
            Text("You changed some settings via Siri during this ride. Would you like to keep these changes?")
        }
    }
    

    // MARK: - Navigation Bar

    @ViewBuilder
    private var navigationBar: some View {
        if telemetry.isOffRoute {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.red)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Off Route")
                        .font(.headline)
                        .foregroundStyle(.red)
                    if let dist = telemetry.distanceOffRoute {
                        Text("+\(formatDistance(dist)) from route")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.75))
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let dir = telemetry.nextTurnDirection {
            HStack(spacing: 6) {
                Image(systemName: telemetry.nextTurnIcon ?? "arrow.triangle.turn.up.right.diamond")
                    .font(.title3.weight(.bold))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(dir.capitalized)
                            .font(.headline)
                        if let dist = telemetry.distanceToNextTurn {
                            Text("in \(formatDistance(dist))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let cue = telemetry.nextTurnCue, !cue.isEmpty {
                        MarqueeText(text: cue, font: .subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.cyan.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let remaining = telemetry.routeDistanceRemaining {
            HStack(spacing: 8) {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.secondary)
                Text("\(formatDistance(remaining)) remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                if let eta = estimatedTimeRemaining {
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("~\(formatTime(eta))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
                Spacer()
            }
            .padding(12)
        }
    }

    // MARK: - Controls

    private var controlBar: some View {
        VStack(spacing: 12) {
            // Primary stats row
            HStack(spacing: 0) {
                statCell(label: "Distance", value: formatDistance(telemetry.totalDistance))
                Divider().frame(height: 36)
                statCell(label: "Moving", value: formatTime(telemetry.movingTime))
                Divider().frame(height: 36)
                statCell(label: "Avg Speed", value: formatSpeed(telemetry.averageSpeed))
            }
            .padding(.vertical, 8)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))

            // Route selector
            Button {
                showRoutePicker = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map")
                        .foregroundStyle(.secondary)
                    Text(activeRoute?.name ?? "Free Ride")
                        .font(.subheadline)
                        .foregroundStyle(activeRoute == nil ? .secondary : .primary)
                        .lineLimit(1)
                    Spacer()
                    Image(systemName: "chevron.up.chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .sheet(isPresented: $showRoutePicker) {
                RoutePickerSheet(
                    routes: routeStore.routes,
                    routeIDsOnWatch: connectivity.routeIDsOnWatch,
                    activeRoute: activeRoute
                ) { selected in
                    switchRoute(selected)
                }
            }
            .sheet(isPresented: $showRouteDetail) {
                if let route = activeRoute {
                    NavigationStack {
                        RouteDetailView(
                            route: route,
                            isOnWatch: connectivity.routeIDsOnWatch.contains(route.id),
                            isUploading: false,
                            isQueued: false,
                            isUploadBlocked: false,
                            canSendToWatch: connectivity.isPaired && connectivity.isWatchAppInstalled,
                            onSend: {
                                ConnectivityManager.shared.sendRoute(route) { _ in }
                            }
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showRouteDetail = false }
                            }
                        }
                    }
                }
            }

            // Quick-link pill: jump to the active route's detail screen
            // without leaving the ride control flow.
            if activeRoute != nil {
                Button {
                    showRouteDetail = true
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: "map.fill")
                            .font(.caption)
                        Text("View Route Details")
                            .font(.caption.weight(.semibold))
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color(.secondarySystemGroupedBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
                .foregroundStyle(.blue)
            }

            // Remaining distance / ETA / auto-pause row
            if telemetry.routeDistanceRemaining != nil || telemetry.isAutoPaused {
                HStack(spacing: 6) {
                    if let remaining = telemetry.routeDistanceRemaining {
                        Image(systemName: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatDistance(remaining)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        if let eta = estimatedTimeRemaining {
                            Text("·")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                            Image(systemName: "clock")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("~\(formatTime(eta)) left")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    Spacer()
                    if telemetry.isAutoPaused {
                        Label("Auto-Paused", systemImage: "pause.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(.yellow)
                    }
                }
                .padding(.horizontal, 4)
            }

            // Action buttons
            HStack(spacing: 10) {
                // Pause / Resume
                Button {
                    if session.isPaused {
                        session.optimisticResume()
                    } else {
                        session.optimisticPause()
                    }
                } label: {
                    HStack(spacing: 6) {
                        if pauseResumeBusy {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                        } else {
                            Image(systemName: session.isPaused ? "play.fill" : "pause.fill")
                        }
                        Text(session.isPaused ? "Resume" : "Pause")
                    }
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.isPaused ? .green : .yellow)
                .disabled(controlsBusy)

                // Hold Ride
                Button {
                    if rideStore.heldRide != nil {
                        showHoldConflictAlert = true
                    } else {
                        showHoldConfirmation = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isHolding {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text("Holding…")
                                .font(.headline)
                        } else {
                            Label("Hold", systemImage: "hand.raised.fill")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.orange)
                .disabled(controlsBusy)
                .confirmationDialog("Put ride on hold?", isPresented: $showHoldConfirmation, titleVisibility: .visible) {
                    Button("Hold Ride") {
                        session.optimisticHold()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Your data will be saved. Resume from the watch or ride list later.")
                }
                // Another held ride already exists. Only one hold is allowed at
                // a time, so the rider has to either finish the old one or
                // discard it before this ride can go on hold.
                .alert("Hold This Ride?", isPresented: $showHoldConflictAlert) {
                    Button("Save & Hold") {
                        if let existing = rideStore.heldRide {
                            ConnectivityManager.shared.sendFinalizeHeldRide(summary: existing, rideStore: rideStore)
                        }
                        session.optimisticHold()
                    }
                    Button("Discard & Hold", role: .destructive) {
                        if let existing = rideStore.heldRide {
                            ConnectivityManager.shared.sendDiscardRide(rideID: existing.id)
                        }
                        session.optimisticHold()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("You already have a held ride. Save it (finish & keep) or discard it to put this ride on hold.")
                }

                // End Ride
                Button {
                    if telemetry.movingTime < 60 {
                        showDiscardAlert = true
                    } else {
                        showEndConfirmation = true
                    }
                } label: {
                    HStack(spacing: 6) {
                        if isEnding {
                            ProgressView()
                                .progressViewStyle(.circular)
                                .tint(.white)
                            Text("Ending…")
                                .font(.headline)
                        } else {
                            Label("End", systemImage: "stop.fill")
                                .font(.headline)
                        }
                    }
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
                .disabled(controlsBusy)
            }
        }
    }

    private func switchRoute(_ route: Route) {
        activeRoute = route
        showRoutePicker = false

        let message: [String: Any] = [
            "type": "changeRoute",
            "routeID": route.id.uuidString
        ]

        if connectivity.routeIDsOnWatch.contains(route.id) {
            // Already on watch — just send the command
            ConnectivityManager.shared.sendRideCommand(message)
        } else {
            // Transfer the route first, then issue the change command
            ConnectivityManager.shared.sendRoute(
                route,
                pendingAction: "changeRoute"
            ) { _ in
                ConnectivityManager.shared.sendRideCommand(message)
            }
        }
    }

    private func checkSettingsRevert() {
        if userSettings.hasUnsavedRideChanges {
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                showSettingsRevertPrompt = true
            }
        }
    }

    // MARK: - ETA estimation

    /// Append the latest telemetry sample to the rolling buffer and trim old
    /// entries. Only appends when moving time has actually advanced, so pauses
    /// don't pollute the recent-split speed calculation.
    private func updateRecentSpeedSamples() {
        let sample = (movingTime: telemetry.movingTime, distance: telemetry.totalDistance)
        if let last = recentSpeedSamples.last, sample.movingTime <= last.movingTime + 0.5 {
            return
        }
        recentSpeedSamples.append(sample)
        let cutoff = sample.movingTime - 180
        recentSpeedSamples.removeAll { $0.movingTime < cutoff }
    }

    /// Recent split average speed (m/s) derived from the rolling buffer, or nil
    /// if there isn't yet enough data (need at least ~20s of moving time).
    private var recentAverageSpeed: Double? {
        guard let first = recentSpeedSamples.first,
              let last = recentSpeedSamples.last else { return nil }
        let dt = last.movingTime - first.movingTime
        let dd = last.distance - first.distance
        guard dt >= 20, dd > 0 else { return nil }
        return dd / dt
    }

    /// Weighted blend of total-ride avg speed and recent split speed, scaled by
    /// the net climb/descent of the remaining route. Returns nil while we don't
    /// have a route remaining distance or enough speed data to be meaningful.
    private var estimatedTimeRemaining: TimeInterval? {
        guard let remaining = telemetry.routeDistanceRemaining, remaining > 0 else { return nil }

        let totalAvg = telemetry.averageSpeed
        let recentAvg = recentAverageSpeed
        let hasTotal = totalAvg > 0.5
        let hasRecent = (recentAvg ?? 0) > 0.5

        let blendedSpeed: Double
        if hasTotal, hasRecent, let recent = recentAvg {
            blendedSpeed = 0.4 * totalAvg + 0.6 * recent
        } else if hasTotal {
            blendedSpeed = totalAvg
        } else if hasRecent, let recent = recentAvg {
            blendedSpeed = recent
        } else {
            return nil
        }

        let adjusted = blendedSpeed / elevationScalingFactor(remainingDistance: remaining)
        guard adjusted > 0.1 else { return nil }
        return remaining / adjusted
    }

    /// Multiplier ≥ 1 if the remaining route net-climbs, < 1 if it net-descends.
    /// Caller divides a flat-ground speed estimate by this. Uses a ~10% speed
    /// adjustment per 1% net grade, clamped to a sane range.
    private func elevationScalingFactor(remainingDistance: Double) -> Double {
        guard let route = activeRoute,
              let series = route.watchElevationSeries,
              series.count >= 2,
              route.distance > 0 else { return 1.0 }

        let covered = max(0, route.distance - remainingDistance)

        var gain: Double = 0
        var loss: Double = 0
        let minDelta: Double = 4.0
        var ref: Double?

        for sample in series where sample.distanceFromStart >= covered {
            guard let r = ref else { ref = sample.elevation; continue }
            let delta = sample.elevation - r
            if delta > minDelta {
                gain += delta
                ref = sample.elevation
            } else if delta < -minDelta {
                loss += -delta
                ref = sample.elevation
            }
        }

        let netGrade = (gain - loss) / remainingDistance
        let factor = 1.0 + netGrade * 10.0
        return min(max(factor, 0.6), 2.0)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.title3.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Route Picker Sheet

private struct RoutePickerSheet: View {
    let routes: [Route]
    let routeIDsOnWatch: Set<UUID>
    let activeRoute: Route?
    let onSelect: (Route) -> Void

    @Environment(\.dismiss) private var dismiss

    private var onWatch: [Route] {
        routes
            .filter { routeIDsOnWatch.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var phoneOnly: [Route] {
        routes
            .filter { !routeIDsOnWatch.contains($0.id) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        NavigationView {
            List {
                if !onWatch.isEmpty {
                    Section("On Watch") {
                        ForEach(onWatch) { route in
                            routeRow(route)
                        }
                    }
                }

                if !phoneOnly.isEmpty {
                    Section("Phone Only") {
                        ForEach(phoneOnly) { route in
                            routeRow(route)
                        }
                    }
                }

                if routes.isEmpty {
                    ContentUnavailableView(
                        "No Routes",
                        systemImage: "map",
                        description: Text("Import a GPX file to get started.")
                    )
                }
            }
            .navigationTitle("Switch Route")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func routeRow(_ route: Route) -> some View {
        Button {
            onSelect(route)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(route.name)
                        .foregroundStyle(.primary)
                    Text(formatRouteDistance(route.distance))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer()
                if route.id == activeRoute?.id {
                    Image(systemName: "checkmark")
                        .foregroundStyle(.accent)
                        .font(.subheadline.weight(.semibold))
                }
            }
        }
    }

    private func formatRouteDistance(_ meters: Double) -> String {
        let useImperial = UnitState.shared.preferences.distance == .miles
        if useImperial {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        } else {
            let km = meters / 1000
            return String(format: "%.1f km", km)
        }
    }
}

// MARK: - Metric Page View

private struct MetricPageView: View {
    let page: MetricPage
    @ObservedObject var telemetry: PhoneTelemetryStore

    var body: some View {
        VStack(spacing: 0) {
            Text(page.name)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, 8)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 0),
                    GridItem(.flexible(), spacing: 0)
                ],
                spacing: 0
            ) {
                ForEach(page.slots) { slot in
                    if slot.type == .elapsedTime {
                        // Tick live every second from the derived ride start time,
                        // so this matches the watch instead of waiting for telemetry pushes.
                        TimelineView(.periodic(from: .now, by: 1)) { context in
                            let value = liveElapsedTime(at: context.date)
                            MetricCell(
                                icon: slot.type.icon,
                                label: slot.type.label,
                                value: value,
                                unit: slot.type.unit
                            )
                        }
                    } else {
                        let resolved = telemetry.resolve(slot.type)
                        MetricCell(
                            icon: slot.type.icon,
                            label: resolved.label,
                            value: resolved.value,
                            unit: resolved.unit
                        )
                    }
                }
            }
            .padding(.horizontal)

            Spacer()
        }
    }

    private func liveElapsedTime(at date: Date) -> String {
        guard let start = telemetry.rideStartTime else {
            return formatTime(telemetry.elapsedTime)
        }
        return formatTime(max(0, date.timeIntervalSince(start)))
    }
}

private struct MetricCell: View {
    let icon: String
    let label: String
    let value: String
    let unit: String

    var body: some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.weight(.bold))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            HStack(spacing: 2) {
                Text(label)
                    .font(.caption2)
                if !unit.isEmpty {
                    Text(unit)
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }
}
#endif
