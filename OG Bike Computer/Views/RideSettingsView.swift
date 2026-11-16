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

            if userSettings.settings.ridePreferences != .default {
                Section {
                    Button("Reset Ride Settings to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Ride Settings", preset: userSettings.activePresetName)
        .alert("Reset Ride Settings to Defaults?", isPresented: $showResetConfirm) {
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

    // MARK: - Stops

    @ViewBuilder
    private var autoPauseSection: some View {
        let mode = userSettings.settings.ridePreferences.autoPause.mode

        Section {
            Picker("Stops", selection: prefs.autoPause.mode) {
                ForEach(StopMode.allCases, id: \.self) { mode in
                    Text(mode.label).tag(mode)
                }
            }
            .pickerStyle(.segmented)
            .labelsHidden()

            if mode == .autoPause {
                PauseSpeedPicker(mps: prefs.autoPause.speedThreshold)
                ResumeProbeIntervalPicker(seconds: prefs.autoPause.resumeProbeInterval)
            }
        } header: {
            Label("Stops", systemImage: "pause.circle")
        } footer: {
            switch mode {
            case .autoPause:
                Text("Pauses the ride when speed drops below the pause speed. While paused, the watch briefly wakes GPS at the resume check interval to detect movement. Shorter intervals resume faster but use more battery.")
            case .detectStops:
                Text("Keeps recording through stops, but standing still or walking around adds no moving time or distance, and stairs add no climbing. Uses the watch's step counter to tell walking from slow riding.")
            case .recordAll:
                Text("Counts everything you record. Moving time matches elapsed time, and walking and stairs add to distance and climbing. Only clear GPS and barometer errors are filtered.")
            }
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
}

// MARK: - Preview

private func previewStore(_ mode: StopMode) -> UserSettingsStore {
    let store = UserSettingsStore()
    store.settings.ridePreferences.autoPause.mode = mode
    return store
}

#Preview("Stops: Auto-Pause") {
    NavigationStack {
        RideSettingsView(userSettings: previewStore(.autoPause), metricConfig: MetricConfigStore())
    }
}

#Preview("Stops: Record All, large text") {
    NavigationStack {
        RideSettingsView(userSettings: previewStore(.recordAll), metricConfig: MetricConfigStore())
    }
    .dynamicTypeSize(.xxxLarge)
}

#Preview("Stops: Detect Stops, iPhone SE width") {
    NavigationStack {
        RideSettingsView(userSettings: previewStore(.detectStops), metricConfig: MetricConfigStore())
    }
    .frame(width: 320)
}
