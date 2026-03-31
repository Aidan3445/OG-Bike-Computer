//
//  NavigationAlertSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

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
            splitAlertsSection
            autoPauseAlertsSection
            descentAlertsSection
            climbAlertsSection
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
            HStack {
                Spacer()
                Text("EXPERIMENTAL")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.orange)
                    .clipShape(Capsule())
                Text("Features below are new.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .listRowBackground(Color.clear)
        }

        Section {
            Toggle("Split Updates", isOn: prefs.splitAlerts.enabled)

            if userSettings.settings.navigationAlerts.splitAlerts.enabled {
                AlertModePicker(label: "Mode", mode: prefs.splitAlerts.mode)

                SplitDistancePicker(meters: prefs.splitAlerts.splitDistance)

                NavigationLink {
                    SplitMetricPickerView(metrics: prefs.splitAlerts.metrics)
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

    // MARK: - Descent Alerts

    @ViewBuilder
    private var descentAlertsSection: some View {
        Section {
            Toggle("Descent Alerts", isOn: prefs.descentAlerts.enabled)

            if userSettings.settings.navigationAlerts.descentAlerts.enabled {
                AlertModePicker(label: "Mode", mode: prefs.descentAlerts.mode)

                SpeedPicker(
                    label: "Speed Threshold",
                    mps: prefs.descentAlerts.speedThreshold,
                    min: 8.94,    // ~20mph / 30kph
                    max: 22.35    // ~50mph / 80kph
                )
            }
        } header: {
            Label("Descent Alerts", systemImage: "arrow.down.right")
        } footer: {
            Text("Announce max speed and stats after a high-speed descent.")
        }
    }

    // MARK: - Climb Alerts

    @ViewBuilder
    private var climbAlertsSection: some View {
        Section {
            Toggle("Climb Alerts", isOn: prefs.climbAlerts.enabled)

            if userSettings.settings.navigationAlerts.climbAlerts.enabled {
                AlertModePicker(label: "Mode", mode: prefs.climbAlerts.mode)

                ElevationPicker(
                    label: "Min Climb Height",
                    meters: prefs.climbAlerts.minimumClimbHeight,
                    min: 15,     // ~50ft / 15m
                    max: 150     // ~500ft / 150m
                )

                DistancePicker(
                    label: "Min Climb Distance",
                    meters: prefs.climbAlerts.minimumClimbDistance,
                    min: 100,    // ~300ft / 100m
                    max: 2000    // ~1.2mi / 2km
                )

                DistancePicker(
                    label: "Climb Separation",
                    meters: prefs.climbAlerts.climbSeparationDistance,
                    min: 50,     // ~150ft / 50m
                    max: 500     // ~1600ft / 500m
                )
            }
        } header: {
            Label("Climb Alerts", systemImage: "arrow.up.right")
        } footer: {
            Text("Announce elevation gain, distance, and peak at the start of a climb.")
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
        } header: {
            Label("Haptic Feedback", systemImage: "hand.point.up.braille")
        } footer: {
            Text("Controls vibration strength for all navigation haptics.")
        }
    }
}
