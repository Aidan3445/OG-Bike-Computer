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
import MapKit
import CoreLocation

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

    /// Pale red in light mode so the dark text on top stays readable.
    private static let offRouteBackground = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? UIColor(red: 0.12, green: 0.02, blue: 0.02, alpha: 1)
            : UIColor(red: 1.0, green: 0.90, blue: 0.90, alpha: 1)
    })

    /// System yellow washes out on light backgrounds, so light mode uses amber.
    private static let autoPausedTint = Color(uiColor: UIColor { traits in
        traits.userInterfaceStyle == .dark
            ? .systemYellow
            : UIColor(red: 0.70, green: 0.48, blue: 0.0, alpha: 1)
    })

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
        .background(telemetry.isOffRoute ? Self.offRouteBackground : Color(.systemGroupedBackground))
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
            Button("Update \(userSettings.activePresetName)") {
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
                        .lineLimit(1)
                    if let dist = telemetry.distanceOffRoute {
                        Text("+\(formatDistance(dist)) from route")
                            .font(.subheadline)
                            .foregroundStyle(.red.opacity(0.75))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
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
                            .lineLimit(1)
                        if let dist = telemetry.distanceToNextTurn {
                            Text("in \(formatDistance(dist))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .fixedSize()
                        }
                    }
                    if let cue = telemetry.nextTurnCue, !cue.isEmpty {
                        MarqueeText(text: cue, font: .subheadline, padding: 2)
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
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
                if let eta = estimatedTimeRemaining {
                    Text("·")
                        .font(.subheadline)
                        .foregroundStyle(.tertiary)
                    Image(systemName: "clock")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("~\(formatETA(eta))")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
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
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
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
                            },
                            recordingPath: telemetry.riderPath
                        )
                        .toolbar {
                            ToolbarItem(placement: .topBarTrailing) {
                                Button("Done") { showRouteDetail = false }
                            }
                        }
                    }
                } else {
                    FreeRideMapSheet()
                }
            }

            // Quick-link pill: jump to the ride map (route + live recording
            // breadcrumb) without leaving the ride control flow.
            Button {
                showRouteDetail = true
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "map.fill")
                        .font(.caption)
                    Text("View Map")
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

            // Remaining distance / ETA / auto-pause row
            if telemetry.routeDistanceRemaining != nil || telemetry.isAutoPaused {
                HStack(spacing: 6) {
                    if let remaining = telemetry.routeDistanceRemaining {
                        // Drop the words before truncating the numbers.
                        ViewThatFits(in: .horizontal) {
                            remainingRow(remaining, withWords: true)
                            remainingRow(remaining, withWords: false)
                        }
                    }
                    Spacer(minLength: 0)
                    if telemetry.isAutoPaused {
                        Label("Auto-Paused", systemImage: "pause.circle.fill")
                            .font(.caption.weight(.medium))
                            .foregroundStyle(Self.autoPausedTint)
                            .fixedSize()
                            .layoutPriority(1)
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

    private func remainingRow(_ remaining: Double, withWords: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: "flag.checkered")
                .foregroundStyle(.secondary)
            Text(formatDistance(remaining) + (withWords ? " remaining" : ""))
                .foregroundStyle(.secondary)
            if let eta = estimatedTimeRemaining {
                Text("·")
                    .foregroundStyle(.tertiary)
                Image(systemName: "clock")
                    .foregroundStyle(.secondary)
                Text("~\(formatETA(eta))" + (withWords ? " left" : ""))
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .font(.caption)
        .lineLimit(1)
        .minimumScaleFactor(withWords ? 1 : 0.8)
    }

    private func switchRoute(_ route: Route?) {
        activeRoute = route
        showRoutePicker = false

        guard let route else {
            // No routeID tells the watch to drop the route and keep recording.
            ConnectivityManager.shared.sendRideCommand(["type": "changeRoute"])
            return
        }

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

    /// Remaining route distance at the ride's average moving speed, scaled by
    /// the net climb or descent ahead. Current speed swings too much to use.
    private var estimatedTimeRemaining: TimeInterval? {
        guard let remaining = telemetry.routeDistanceRemaining, remaining > 0,
              telemetry.averageSpeed > 0.5 else { return nil }
        let adjusted = telemetry.averageSpeed / elevationScalingFactor(remainingDistance: remaining)
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
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Free Ride Map Sheet

/// Map for free rides — no planned route, just the live recording breadcrumb
/// and the rider's current position.
private struct FreeRideMapSheet: View {
    @ObservedObject private var telemetry = PhoneTelemetryStore.shared
    @Environment(\.dismiss) private var dismiss
    @State private var mapPosition: MapCameraPosition = .userLocation(fallback: .automatic)

    var body: some View {
        NavigationStack {
            Map(position: $mapPosition) {
                if telemetry.riderPath.count >= 2 {
                    MapPolyline(coordinates: telemetry.riderPath)
                        .stroke(.purple.opacity(0.8), lineWidth: 4)
                }

                if let first = telemetry.riderPath.first {
                    Annotation("Start", coordinate: first) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .flat))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .navigationTitle("Free Ride")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Route Picker Sheet

private struct RoutePickerSheet: View {
    let routes: [Route]
    let routeIDsOnWatch: Set<UUID>
    let activeRoute: Route?
    let onSelect: (Route?) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var showFreeRideConfirmation = false

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
                if activeRoute != nil {
                    Section {
                        Button {
                            showFreeRideConfirmation = true
                        } label: {
                            Label("Free Ride", systemImage: "bicycle")
                                .foregroundStyle(.primary)
                        }
                    }
                }

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
            .confirmationDialog("Switch to Free Ride?", isPresented: $showFreeRideConfirmation, titleVisibility: .visible) {
                Button("Free Ride") { onSelect(nil) }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Turn-by-turn navigation will stop.")
            }
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
        // Short screens (SE, large text) step down to denser cells so every
        // metric stays visible without scrolling.
        ViewThatFits(in: .vertical) {
            pageContent(.regular)
            pageContent(.compact)
            pageContent(.tight)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    private func pageContent(_ density: MetricCellDensity) -> some View {
        VStack(spacing: 0) {
            Text(page.name)
                .font(.headline)
                .foregroundStyle(.secondary)
                .padding(.top, density == .regular ? 8 : 2)

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
                                unit: slot.type.unit,
                                density: density
                            )
                        }
                    } else {
                        let resolved = telemetry.resolve(slot.type)
                        MetricCell(
                            icon: slot.type.icon,
                            label: resolved.label,
                            value: resolved.value,
                            unit: resolved.unit,
                            density: density
                        )
                    }
                }
            }
            .padding(.horizontal)
        }
    }

    private func liveElapsedTime(at date: Date) -> String {
        guard let start = telemetry.rideStartTime else {
            return formatTime(telemetry.elapsedTime)
        }
        return formatTime(max(0, date.timeIntervalSince(start)))
    }
}

/// Compact drops the icon and tightens padding. Tight also shrinks the value.
private enum MetricCellDensity {
    case regular, compact, tight
}

private struct MetricCell: View {
    let icon: String
    let label: String
    let value: String
    let unit: String
    let density: MetricCellDensity

    var body: some View {
        VStack(spacing: density == .regular ? 4 : 1) {
            if density == .regular {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Text(value)
                .font(density == .tight ? .title3.weight(.bold) : .title2.weight(.bold))
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
            .lineLimit(1)
            .minimumScaleFactor(0.75)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, density == .regular ? 12 : 4)
    }
}

// MARK: - Previews

/// Worst-case ride for layout checks: long values, auto-paused, a long route
/// name, and either off route or approaching a turn.
private func previewRideControl(offRoute: Bool) -> some View {
    let route = Route(name: "Saturday Long Loop Through the Blue Hills and Back Along the Neponset River", points: [])
    let routeStore = RouteStore()
    routeStore.routes = [route]

    let t = PhoneTelemetryStore.shared
    t.elapsedTime = 11 * 3600 + 2 * 60 + 37
    t.movingTime = 10 * 3600 + 45 * 60 + 12
    t.totalDistance = 181_000
    t.averageSpeed = 8.4
    t.currentSpeed = 10.2
    t.heartRate = 152
    t.isAutoPaused = true
    t.activeRouteID = route.id
    t.routeDistanceRemaining = 154_300
    t.isOffRoute = offRoute
    t.distanceOffRoute = offRoute ? 1_840 : nil
    t.nextTurnDirection = offRoute ? nil : "Slight Right"
    t.nextTurnIcon = offRoute ? nil : "arrow.turn.up.right"
    t.distanceToNextTurn = offRoute ? nil : 480
    t.nextTurnCue = offRoute ? nil : "onto Old Colony Boulevard"

    return NavigationStack {
        RideControlView(
            metricConfig: MetricConfigStore(),
            userSettings: UserSettingsStore(),
            routeStore: routeStore,
            rideStore: RideStore()
        )
    }
}

#Preview("Off route, XL text", traits: .fixedLayout(width: 375, height: 667)) {
    previewRideControl(offRoute: true)
        .environment(\.dynamicTypeSize, .xLarge)
}

#Preview("Off route, XXL text", traits: .fixedLayout(width: 375, height: 667)) {
    previewRideControl(offRoute: true)
        .environment(\.dynamicTypeSize, .xxLarge)
}

#Preview("Turn ahead, XL text", traits: .fixedLayout(width: 375, height: 667)) {
    previewRideControl(offRoute: false)
        .environment(\.dynamicTypeSize, .xLarge)
}

#Preview("Turn ahead, XXL text", traits: .fixedLayout(width: 375, height: 667)) {
    previewRideControl(offRoute: false)
        .environment(\.dynamicTypeSize, .xxLarge)
}
#endif
