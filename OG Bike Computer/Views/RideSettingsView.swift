//
//  RideSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct RideSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject private var unitState = UnitState.shared
    @State private var showResetConfirm = false

    private var prefs: Binding<RidePreferences> {
        $userSettings.settings.ridePreferences
    }

    var body: some View {
        Form {
            tabOrderSection
            autoPauseSection
            checkpointSection
            phoneAlertsSection

            if userSettings.settings.ridePreferences != .default {
                Section {
                    Button("Reset Ride Settings to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Ride Settings", preset: userSettings.activePresetName)
        .confirmationDialog(
            "Reset Ride Settings to Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                userSettings.settings.ridePreferences = .default
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All ride settings will be restored to their defaults.")
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

    // MARK: - Tab Order

    @ViewBuilder
    private var tabOrderSection: some View {
        Section {
            NavigationLink {
                TabOrderingView(userSettings: userSettings, metricConfig: metricConfig)
            } label: {
                HStack {
                    Text("Tab Order")
                    Spacer()
                    Text(userSettings.settings.ridePreferences.tabOrder == nil ? "Default" : "Custom")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Watch Layout", systemImage: "rectangle.split.3x1")
        } footer: {
            Text("Reorder the screens you swipe through on the watch during a ride.")
        }
    }

    // MARK: - Auto-Pause

    @ViewBuilder
    private var autoPauseSection: some View {
        Section {
            Toggle("Auto-Pause", isOn: prefs.autoPause.enabled)

            if userSettings.settings.ridePreferences.autoPause.enabled {
                PauseSpeedPicker(mps: prefs.autoPause.speedThreshold)
                ResumeProbeIntervalPicker(seconds: prefs.autoPause.resumeProbeInterval)
            }
        } header: {
            Label("Auto-Pause", systemImage: "pause.circle")
        } footer: {
            Text("Automatically pause the ride when speed drops below the threshold. While paused, the watch briefly wakes GPS at the resume check interval to detect movement — shorter intervals resume faster but use more battery.")
        }
    }

    // MARK: - Checkpoint Caching

    @ViewBuilder
    private var checkpointSection: some View {
        Section {
            Picker("Save Interval", selection: prefs.checkpointInterval) {
                ForEach(CheckpointInterval.allCases, id: \.self) { interval in
                    Text(interval.label).tag(interval)
                }
            }
        } header: {
            Label("Crash Recovery", systemImage: "externaldrive.badge.checkmark")
        } footer: {
            Text("Periodically saves ride data to disk. If the app crashes, data up to the last checkpoint is recovered on next launch as a held ride you can continue or save.")
        }
    }

    // MARK: - Live Activity

    @ViewBuilder
    private var phoneAlertsSection: some View {
        Section {
            NavigationLink {
                PhoneAlertSettingsView(userSettings: userSettings)
            } label: {
                HStack {
                    Text("Live Activity")
                    Spacer()
                    Text(userSettings.settings.phoneAlerts.showTurnNotifications
                         ? "Notifications on"
                         : "Stats only")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Label("Live Activity", systemImage: "iphone")
        } footer: {
            Text("Customize the ride Live Activity stats and optional turn notifications on your iPhone.")
        }
    }
}
