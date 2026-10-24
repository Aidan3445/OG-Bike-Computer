//
//  NavigationAlertSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI
import UIKit

// MARK: - Main View

struct NavigationAlertSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    var metricConfig: MetricConfigStore
    @ObservedObject private var unitState = UnitState.shared
    @State private var showResetConfirm = false

    private var prefs: Binding<NavigationAlertPreferences> {
        $userSettings.settings.navigationAlerts
    }

    var body: some View {
        Form {
            turnAlertsSection
            waypointAlertsSection
            progressUpdatesSection
            routeStatusSection
            autoPauseAlertsSection
            audioOutputSection
            hapticsSection
            watchDisplaySection

            if userSettings.settings.navigationAlerts != .default {
                Section {
                    Button("Reset Alerts to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Alerts", preset: userSettings.activePresetName)
        .confirmationDialog(
            "Reset Alerts to Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                userSettings.settings.navigationAlerts = .default
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All alert settings will be restored to their defaults.")
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsPresetsView(userSettings: userSettings)
                } label: {
                    Image(systemName: "slider.horizontal.2.gobackward")
                }
            }
        }
    }

    // MARK: - Turn Alerts

    @ViewBuilder
    private var turnAlertsSection: some View {
        Section {
            AlertModePicker(label: "Alert Style", mode: prefs.turnAlerts.defaultMode)
        } header: {
            Label("Turn Alerts", systemImage: "arrow.triangle.turn.up.right.diamond")
        }

        Section {
            DistancePicker(
                label: "Primary Distance",
                meters: prefs.turnAlerts.primaryApproachDistance,
                min: 30.48,    // 100ft / 30m
                max: 402.336   // 0.25mi / 500m
            )
        } header: {
            Text("Primary Approach")
        } footer: {
            Text("Distance before a turn to give the first approach alert.")
        }

        Section {
            Toggle("Secondary Approach", isOn: prefs.turnAlerts.secondaryApproachEnabled)

            if userSettings.settings.navigationAlerts.turnAlerts.secondaryApproachEnabled {
                DistancePicker(
                    label: "Secondary Distance",
                    meters: prefs.turnAlerts.secondaryApproachDistance,
                    min: 800,      // 0.5 mi / 800 m
                    max: 3218.69   // 2 mi / 3 km
                )
            }
        } header: {
            Text("Secondary Approach")
        } footer: {
            Text("Optional earlier warning at a greater distance.")
        }

        Section {
            DisclosureGroup("Individual Overrides") {
                OptionalAlertModePicker(
                    label: "At Turn",
                    mode: prefs.turnAlerts.atTurnMode,
                    defaultMode: userSettings.settings.navigationAlerts.turnAlerts.defaultMode
                )
                OptionalAlertModePicker(
                    label: "Primary Approach",
                    mode: prefs.turnAlerts.primaryApproachMode,
                    defaultMode: userSettings.settings.navigationAlerts.turnAlerts.defaultMode
                )
                if userSettings.settings.navigationAlerts.turnAlerts.secondaryApproachEnabled {
                    OptionalAlertModePicker(
                        label: "Secondary Approach",
                        mode: prefs.turnAlerts.secondaryApproachMode,
                        defaultMode: userSettings.settings.navigationAlerts.turnAlerts.defaultMode
                    )
                }
            }
        }
    }

    // MARK: - Progress Updates (stat-reading events)

    @ViewBuilder
    private var progressUpdatesSection: some View {
        Section {
            NavigationLink {
                SplitMetricPickerView(metrics: prefs.splitAlerts.metrics, userSettings: userSettings)
            } label: {
                HStack {
                    Text("Stats to Read")
                    Spacer()
                    Text("\(userSettings.settings.navigationAlerts.splitAlerts.metrics.count) selected")
                        .foregroundStyle(.secondary)
                }
            }

            Toggle("Split Updates", isOn: prefs.splitAlerts.enabled)
            if userSettings.settings.navigationAlerts.splitAlerts.enabled {
                AlertModePicker(label: "Split Mode", mode: prefs.splitAlerts.mode)
                SplitDistancePicker(meters: prefs.splitAlerts.splitDistance)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Halfway")
                Picker("Halfway", selection: prefs.navigationEvents.halfwayAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            Toggle("End-of-Route Readout", isOn: prefs.endOfRouteAlerts.enabled)
            if userSettings.settings.navigationAlerts.endOfRouteAlerts.enabled {
                AlertModePicker(label: "End-of-Route Mode", mode: prefs.endOfRouteAlerts.mode)
            }
        } header: {
            Label("Progress Updates", systemImage: "stopwatch")
        } footer: {
            Text("Read your ride stats at key moments. Split, Halfway, and End-of-Route all use the stats you pick in Stats to Read.")
        }
    }

    // MARK: - Route Status (non-stat events)

    @ViewBuilder
    private var routeStatusSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Off Route")
                Picker("Off Route", selection: prefs.navigationEvents.offRouteAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            DistancePicker(
                label: "Off-Route Threshold",
                meters: prefs.navigationEvents.offRouteThreshold,
                min: 30,   // ~100ft / 30m
                max: 300   // ~1000ft / 300m
            )

            VStack(alignment: .leading, spacing: 4) {
                Text("Back on Route")
                Picker("Back on Route", selection: prefs.navigationEvents.backOnRouteAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Arrival")
                Picker("Arrival", selection: prefs.navigationEvents.arrivalAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }
        } header: {
            Label("Route Status", systemImage: "location.fill")
        } footer: {
            Text("Alerts for route position changes.")
        }
    }

    // MARK: - Auto-Pause Alerts

    @ViewBuilder
    private var autoPauseAlertsSection: some View {
        let autoPauseEnabled = userSettings.settings.ridePreferences.autoPause.enabled

        Section {
            if !autoPauseEnabled {
                NavigationLink {
                    RideSettingsView(userSettings: userSettings, metricConfig: metricConfig)
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "info.circle")
                            .foregroundStyle(.secondary)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Pause is off")
                                .font(.subheadline.weight(.medium))
                            Text("Turn it on in Ride Settings to enable these alerts.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Group {
                Toggle("Auto-Pause Alerts", isOn: prefs.autoPauseAlerts.enabled)

                if userSettings.settings.navigationAlerts.autoPauseAlerts.enabled {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Paused")
                        Picker("Paused", selection: prefs.autoPauseAlerts.pauseMode) {
                            ForEach(AlertMode.allCases, id: \.self) { m in
                                Text(m.shortLabel).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }

                    VStack(alignment: .leading, spacing: 4) {
                        Text("Resumed")
                        Picker("Resumed", selection: prefs.autoPauseAlerts.resumeMode) {
                            ForEach(AlertMode.allCases, id: \.self) { m in
                                Text(m.shortLabel).tag(m)
                            }
                        }
                        .pickerStyle(.segmented)
                    }
                }
            }
            .disabled(!autoPauseEnabled)
        } header: {
            Label("Auto-Pause Alerts", systemImage: "pause.circle")
        } footer: {
            Text("Alert when the ride auto-pauses or resumes.")
        }
    }

    // MARK: - Waypoint / POI Alerts

    @ViewBuilder
    private var waypointAlertsSection: some View {
        Section {
            Toggle("Waypoint Alerts", isOn: prefs.waypointAlerts.enabled)

            if userSettings.settings.navigationAlerts.waypointAlerts.enabled {
                AlertModePicker(label: "Mode", mode: prefs.waypointAlerts.mode)

                MaxOffRouteRangeField(meters: prefs.waypointAlerts.maxOffRouteDistance)
            }
        } header: {
            Label("Waypoint Alerts", systemImage: "mappin.and.ellipse")
        } footer: {
            Text("Announce POIs along the route with a specified max distance from the route. E.g. \"in 500ft (150m) the world's largest spork is 0.5mi (800m) to your right\".")
        }
    }

    // MARK: - Haptics

    @ViewBuilder
    private var hapticsSection: some View {
        Section {
            Picker("Haptic Intensity", selection: prefs.haptics.intensity) {
                ForEach(HapticIntensity.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: prefs.haptics.intensity.wrappedValue) { _, newValue in
                // Preview the haptic on the WATCH (that's the device the
                // setting actually affects). Phone preview was misleading.
                ConnectivityManager.shared.sendSampleHaptic(intensity: newValue.rawValue)
            }
        } header: {
            Label("Haptic Feedback", systemImage: "hand.point.up.braille")
        } footer: {
            Text("Controls vibration strength for all navigation haptics.")
        }
    }

    // MARK: - Audio Output

    @ViewBuilder
    private var audioOutputSection: some View {
        Section {
            Picker("Audio Source", selection: prefs.audioOutput.source) {
                ForEach(AlertAudioSource.allCases, id: \.self) { source in
                    Text(source.label).tag(source)
                }
            }
            .pickerStyle(.segmented)

            Text(userSettings.settings.navigationAlerts.audioOutput.source.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Label("Audio Source", systemImage: "speaker.wave.2")
        } footer: {
            Text("Auto plays through watch headphones when connected, otherwise your iPhone, falling back to the watch speaker.")
        }
    }

    // MARK: - Watch Display

    @ViewBuilder
    private var watchDisplaySection: some View {
        Section {
            Toggle("Wake Screen on Alert", isOn: $userSettings.settings.ridePreferences.wakeOnAlert)
        } header: {
            Label("Watch Display", systemImage: "applewatch")
        } footer: {
            Text("Sends a time-sensitive notification to light up the watch display when a navigation alert fires.")
        }
    }
}

// MARK: - Max Off-Route Range Field

/// Numeric input for the waypoint-alerts max off-route range.
/// Bounds: 0.5–10 mi (0.5–16 km depending on units). Value is clamped on commit.
private struct MaxOffRouteRangeField: View {
    @Binding var meters: Double
    @State private var text: String = ""
    @FocusState private var focused: Bool

    private var isImperial: Bool { currentUnits.distance == .miles }

    private var unitLabel: String { isImperial ? "mi" : "km" }
    private var minValue: Double { 0.5 }
    private var maxValue: Double { isImperial ? 10 : 16 }
    private var metersPerUnit: Double { isImperial ? 1609.34 : 1000 }

    private var displayValue: Double {
        meters / metersPerUnit
    }

    var body: some View {
        HStack {
            Text("Max Off-Route Range")
            Spacer()
            TextField("", text: $text)
                .keyboardType(.decimalPad)
                .focused($focused)
                .multilineTextAlignment(.trailing)
                .frame(maxWidth: 80)
                .onAppear { syncFromMeters() }
                .onChange(of: meters) { _, _ in
                    if !focused { syncFromMeters() }
                }
                .onChange(of: focused) { _, isFocused in
                    if !isFocused { commit() }
                }
            Text(unitLabel)
                .foregroundStyle(.secondary)
        }
    }

    private func syncFromMeters() {
        let v = displayValue
        // 1 decimal place is enough for this range
        text = String(format: v == v.rounded() ? "%.0f" : "%.1f", v)
    }

    private func commit() {
        let normalized = text.replacingOccurrences(of: ",", with: ".")
        guard var parsed = Double(normalized) else {
            syncFromMeters()
            return
        }
        parsed = min(max(parsed, minValue), maxValue)
        meters = parsed * metersPerUnit
        syncFromMeters()
    }
}
