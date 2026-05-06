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
    @ObservedObject private var unitState = UnitState.shared

    private var prefs: Binding<NavigationAlertPreferences> {
        $userSettings.settings.navigationAlerts
    }

    var body: some View {
        Form {
            turnAlertsSection
            navigationEventsSection
            waypointAlertsSection
            splitAlertsSection
            autoPauseAlertsSection
            hapticsSection

            if userSettings.settings.navigationAlerts != .default {
                Section {
                    Button("Reset Navigation Alerts to Defaults", role: .destructive) {
                        userSettings.settings.navigationAlerts = .default
                    }
                }
            }
        }
        .settingsPageTitle("Navigation Alerts", profile: userSettings.activeProfileName)
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
            AlertModePicker(label: "Default Mode", mode: prefs.turnAlerts.defaultMode)
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
                    min: 804.672,  // 0.5mi / 750m
                    max: 3218.69   // 2mi / 3km
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

    // MARK: - Navigation Events

    @ViewBuilder
    private var navigationEventsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Halfway")
                Picker("Halfway", selection: prefs.navigationEvents.halfwayAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Off Route")
                Picker("Off Route", selection: prefs.navigationEvents.offRouteAlert) {
                    ForEach(AlertMode.allCases, id: \.self) { m in
                        Text(m.shortLabel).tag(m)
                    }
                }
                .pickerStyle(.segmented)
            }

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
            Label("Navigation Events", systemImage: "location.fill")
        }

        Section {
            DistancePicker(
                label: "Off-Route Threshold",
                meters: prefs.navigationEvents.offRouteThreshold,
                min: 30,   // ~100ft / 30m
                max: 300   // ~1000ft / 300m
            )
        } footer: {
            Text("How far from the route before you're considered off-route.")
        }
    }

    // MARK: - Split Alerts

    @ViewBuilder
    private var splitAlertsSection: some View {
        Section {
            Toggle("Split Updates", isOn: prefs.splitAlerts.enabled)

            if userSettings.settings.navigationAlerts.splitAlerts.enabled {
                AlertModePicker(label: "Mode", mode: prefs.splitAlerts.mode)

                SplitDistancePicker(meters: prefs.splitAlerts.splitDistance)

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
            }
        } header: {
            Label("Split Updates", systemImage: "stopwatch")
        } footer: {
            Text("Announce ride stats at regular distance intervals. Interrupted by turn alerts.")
        }
    }

    // MARK: - Auto-Pause Alerts

    @ViewBuilder
    private var autoPauseAlertsSection: some View {
        Section {
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

                Toggle("Custom Distances", isOn: prefs.waypointAlerts.useCustomDistances)

                if userSettings.settings.navigationAlerts.waypointAlerts.useCustomDistances {
                    DistancePicker(
                        label: "Primary Distance",
                        meters: prefs.waypointAlerts.primaryApproachDistance,
                        min: 30.48,    // 100ft
                        max: 402.336   // 0.25mi
                    )

                    Toggle("Secondary Approach", isOn: prefs.waypointAlerts.secondaryApproachEnabled)

                    if userSettings.settings.navigationAlerts.waypointAlerts.secondaryApproachEnabled {
                        DistancePicker(
                            label: "Secondary Distance",
                            meters: prefs.waypointAlerts.secondaryApproachDistance,
                            min: 402.336,  // 0.25mi
                            max: 3218.69   // 2mi
                        )
                    }
                }

                MaxOffRouteRangeField(meters: prefs.waypointAlerts.maxOffRouteDistance)
            }
        } header: {
            Label("Waypoint Alerts", systemImage: "mappin.and.ellipse")
        } footer: {
            Text("Announce points of interest along or near the route — e.g. \"in 500ft, pass the world's largest spork\". When custom distances are off, waypoint alerts use the same approach distances as turn alerts.")
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
                let style: UIImpactFeedbackGenerator.FeedbackStyle = switch newValue {
                case .light:  .light
                case .medium: .medium
                case .strong: .heavy
                }
                UIImpactFeedbackGenerator(style: style).impactOccurred()
            }
        } header: {
            Label("Haptic Feedback", systemImage: "hand.point.up.braille")
        } footer: {
            Text("Controls vibration strength for all navigation haptics.")
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
