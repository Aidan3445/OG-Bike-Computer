//
//  RideSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct RideSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject private var unitState = UnitState.shared

    private var prefs: Binding<RidePreferences> {
        $userSettings.settings.ridePreferences
    }

    var body: some View {
        Form {
            autoPauseSection
            autoLapSection
            gpsSensorsSection
            displaySection
            alertsSection
            privacySection
            phoneAlertsSection
        }
        .navigationTitle("Ride Settings")
    }

    // MARK: - Auto-Pause

    @ViewBuilder
    private var autoPauseSection: some View {
        Section {
            Toggle("Auto-Pause", isOn: prefs.autoPause.enabled)

            if userSettings.settings.ridePreferences.autoPause.enabled {
                PauseSpeedPicker(mps: prefs.autoPause.speedThreshold)
            }
        } header: {
            Label("Auto-Pause", systemImage: "pause.circle")
        } footer: {
            Text("Automatically pause the ride when speed drops below the threshold.")
        }
    }

    // MARK: - Auto-Lap

    @ViewBuilder
    private var autoLapSection: some View {
        Section {
            Toggle("Auto-Lap", isOn: prefs.autoLap.enabled)

            if userSettings.settings.ridePreferences.autoLap.enabled {
                SplitDistancePicker(meters: prefs.autoLap.lapDistance)

                AlertModePicker(label: "Lap Alert", mode: prefs.autoLap.mode)
            }
        } header: {
            Label("Auto-Lap", systemImage: "stopwatch")
        } footer: {
            Text("Announce lap splits at regular distance intervals.")
        }
    }

    // MARK: - GPS & Sensors

    @ViewBuilder
    private var gpsSensorsSection: some View {
        Section {
            Picker("GPS Accuracy", selection: prefs.gpsAccuracyFloor) {
                ForEach(GPSAccuracyFloor.allCases, id: \.self) { floor in
                    Text(floor.label).tag(floor)
                }
            }
            .pickerStyle(.segmented)

            Picker("Elevation Smoothing", selection: prefs.elevationSmoothing) {
                ForEach(ElevationSmoothing.allCases, id: \.self) { level in
                    Text(level.label).tag(level)
                }
            }
        } header: {
            Label("GPS & Sensors", systemImage: "location.circle")
        } footer: {
            Text("GPS accuracy sets the minimum quality floor. The app still dynamically reduces GPS near turns to save battery. Higher elevation smoothing filters noise but may miss small hills.")
        }
    }

    // MARK: - Display

    @ViewBuilder
    private var displaySection: some View {
        Section {
            Picker("Map Rotation", selection: prefs.mapRotation) {
                ForEach(MapRotation.allCases, id: \.self) { rotation in
                    Text(rotation.label).tag(rotation)
                }
            }
            .pickerStyle(.segmented)
        } header: {
            Label("Display", systemImage: "map")
        }
    }

    // MARK: - Alerts

    @ViewBuilder
    private var alertsSection: some View {
        Section {
            Toggle("Wake Screen on Alert", isOn: prefs.wakeOnAlert)
        } header: {
            Label("Alerts", systemImage: "bell.badge")
        } footer: {
            Text("Sends a time-sensitive notification to light up the watch display when a navigation alert fires.")
        }
    }

    // MARK: - Privacy

    @ViewBuilder
    private var privacySection: some View {
        Section {
            Picker("Ride Privacy", selection: prefs.ridePrivacy) {
                ForEach(RidePrivacy.allCases, id: \.self) { privacy in
                    Text(privacy.label).tag(privacy)
                }
            }
        } header: {
            Label("Privacy", systemImage: "eye.slash")
        } footer: {
            Text("Removes approximately 200m from the start and end of your recorded track to hide your home location.")
        }
    }

    // MARK: - Phone Alerts

    @ViewBuilder
    private var phoneAlertsSection: some View {
        Section {
            NavigationLink {
                PhoneAlertSettingsView(userSettings: userSettings)
            } label: {
                HStack {
                    Text("Phone Alerts")
                    Spacer()
                    Text(userSettings.settings.phoneAlerts.mode.label)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Phone", systemImage: "iphone")
        } footer: {
            Text("Show turn-by-turn alerts on your iPhone during rides. Requires phone nearby.")
        }
    }
}
