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
    @ObservedObject private var unitState = UnitState.shared

    @State private var showEndConfirmation = false
    @State private var showDiscardAlert = false
    @State private var showSettingsRevertPrompt = false
    @State private var selectedPage = 0

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
        .background(Color(.systemGroupedBackground))
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
                session.endRide()
                checkSettingsRevert()
            }
        } message: {
            Text("This ride is under 1 minute. Do you want to save it anyway?")
        }
        .alert("End Ride?", isPresented: $showEndConfirmation) {
            Button("End & Save", role: .destructive) {
                session.endRide()
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
        if let dir = telemetry.nextTurnDirection {
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
        } else if telemetry.isOffRoute {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(telemetry.offRouteMessage ?? "Off Route")
                    .font(.headline)
                    .foregroundStyle(.orange)
                Spacer()
            }
            .padding(12)
            .background(.orange.opacity(0.12))
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

            // Action buttons
            HStack(spacing: 12) {
                // Pause / Resume
                Button {
                    if session.isPaused {
                        session.resumeRide()
                    } else {
                        session.pauseRide()
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
