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
    @ObservedObject private var unitState = UnitState.shared
    @ObservedObject private var connectivity = ConnectivityManager.shared

    @State private var showEndConfirmation = false
    @State private var showDiscardAlert = false
    @State private var showSettingsRevertPrompt = false
    @State private var showRoutePicker = false
    @State private var activeRoute: Route?
    @State private var selectedPage = 0

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
        .background(telemetry.isOffRoute ? Color(red: 0.12, green: 0.02, blue: 0.02) : Color(.systemGroupedBackground))
        .navigationTitle(session.isPaused ? "Paused" : "Riding")
        .navigationBarTitleDisplayMode(.inline)
        .alert("Discard Ride?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                // Send discard command to watch — don't call session.endRide()
                // because the watch's discard() handles ending the HK session
                ConnectivityManager.shared.sendRideCommand(["type": "discardRide"])
                userSettings.clearRideTracking()
            }
            Button("Save Anyway") {
                session.optimisticEnd()
                checkSettingsRevert()
                dismiss()
            }
        } message: {
            Text("This ride is under 1 minute. Do you want to save it anyway?")
        }
        .alert("End Ride?", isPresented: $showEndConfirmation) {
            Button("End & Save", role: .destructive) {
                session.optimisticEnd()
                checkSettingsRevert()
                dismiss()
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
                        Text(cue)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                Spacer()
            }
            .padding(12)
            .background(.cyan.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        } else if let remaining = telemetry.routeDistanceRemaining {
            HStack {
                Image(systemName: "flag.checkered")
                    .foregroundStyle(.secondary)
                Text("\(formatDistance(remaining)) remaining")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
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
                    routeNamesOnWatch: connectivity.routeNamesOnWatch,
                    activeRoute: activeRoute
                ) { selected in
                    switchRoute(selected)
                }
            }

            // Remaining distance / auto-pause row
            if telemetry.routeDistanceRemaining != nil || telemetry.isAutoPaused {
                HStack {
                    if let remaining = telemetry.routeDistanceRemaining {
                        Image(systemName: "flag.checkered")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(formatDistance(remaining)) remaining")
                            .font(.caption)
                            .foregroundStyle(.secondary)
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
            HStack(spacing: 12) {
                // Pause / Resume
                Button {
                    if session.isPaused {
                        session.optimisticResume()
                    } else {
                        session.optimisticPause()
                    }
                } label: {
                    Label(
                        session.isPaused ? "Resume" : "Pause",
                        systemImage: session.isPaused ? "play.fill" : "pause.fill"
                    )
                    .font(.headline)
                    .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(session.isPaused ? .green : .yellow)

                // End Ride
                Button {
                    if telemetry.movingTime < 60 {
                        showDiscardAlert = true
                    } else {
                        showEndConfirmation = true
                    }
                } label: {
                    Label("End", systemImage: "stop.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity, minHeight: 50)
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
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

        if connectivity.routeNamesOnWatch.contains(route.name) {
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
    let routeNamesOnWatch: Set<String>
    let activeRoute: Route?
    let onSelect: (Route) -> Void

    @Environment(\.dismiss) private var dismiss

    private var onWatch: [Route] {
        routes
            .filter { routeNamesOnWatch.contains($0.name) }
            .sorted { $0.name.localizedCompare($1.name) == .orderedAscending }
    }

    private var phoneOnly: [Route] {
        routes
            .filter { !routeNamesOnWatch.contains($0.name) }
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
    let telemetry: PhoneTelemetryStore

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
                    let resolved = telemetry.resolve(slot.type)
                    MetricCell(
                        icon: slot.type.icon,
                        label: resolved.label,
                        value: resolved.value,
                        unit: resolved.unit
                    )
                }
            }
            .padding(.horizontal)

            Spacer()
        }
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
