//
//  UnitsSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/27/26.
//

import SwiftUI

struct UnitsSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore

    private var prefs: Binding<UnitPreferences> {
        $userSettings.settings.unitPreferences
    }

    /// Binding for the blanket system picker.
    /// Returns the current system (imperial/metric) or nil when custom.
    /// Setting a non-nil value applies the blanket system to all dimensions.
    private var systemBinding: Binding<MeasurementSystem?> {
        Binding(
            get: { userSettings.settings.unitPreferences.system },
            set: { newValue in
                if let system = newValue {
                    userSettings.settings.unitPreferences.apply(system)
                }
            }
        )
    }

    var body: some View {
        Form {
            // MARK: - System Toggle
            Section {
                Picker("Units", selection: systemBinding) {
                    ForEach(MeasurementSystem.allCases, id: \.self) { system in
                        Text(system.label).tag(Optional(system))
                    }
                    if userSettings.settings.unitPreferences.system == nil {
                        Text("Custom").tag(MeasurementSystem?.none)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Advanced
            Section {
                Picker("Speed", selection: prefs.speed) {
                    ForEach(SpeedUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }

                Picker("Distance", selection: prefs.distance) {
                    ForEach(DistanceUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }

                Picker("Elevation", selection: prefs.elevation) {
                    ForEach(ElevationUnit.allCases, id: \.self) { unit in
                        Text(unit.label).tag(unit)
                    }
                }
            } header: {
                Text("Advanced")
            } footer: {
                Text("Override individual units. Changing these will set the system to Custom.")
            }
            if userSettings.settings.unitPreferences != .default {
                Section {
                    Button("Reset Units to Defaults", role: .destructive) {
                        userSettings.settings.unitPreferences = .default
                    }
                }
            }
        }
        .settingsPageTitle("Units", profile: userSettings.activeProfileName)
    }
}
