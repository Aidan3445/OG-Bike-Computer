//
//  UnitsSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/27/26.
//

import SwiftUI

/// Picker sentinel used by `UnitsSettingsView` to represent the three
/// top-level choices: Imperial, Metric, Custom. Independent of the per-
/// dimension values so Custom stays visible even when the dimensions
/// happen to match a clean system.
private enum UnitSystemChoice: String, CaseIterable, Hashable {
    case imperial, metric, custom

    var label: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric: return "Metric"
        case .custom: return "Custom"
        }
    }
}

struct UnitsSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showResetConfirm = false

    private var prefs: Binding<UnitPreferences> {
        $userSettings.settings.unitPreferences
    }

    private var systemChoice: Binding<UnitSystemChoice> {
        Binding(
            get: {
                let p = userSettings.settings.unitPreferences
                if p.isCustom { return .custom }
                switch p.system {
                case .imperial: return .imperial
                case .metric:   return .metric
                case .none:     return .custom
                }
            },
            set: { newValue in
                switch newValue {
                case .imperial: userSettings.settings.unitPreferences.apply(.imperial)
                case .metric:   userSettings.settings.unitPreferences.apply(.metric)
                case .custom:   userSettings.settings.unitPreferences.enterCustom()
                }
            }
        )
    }

    var body: some View {
        Form {
            // MARK: - System
            Section {
                Picker("Units", selection: systemChoice) {
                    ForEach(UnitSystemChoice.allCases, id: \.self) { choice in
                        Text(choice.label).tag(choice)
                    }
                }
                .pickerStyle(.segmented)
            }

            // MARK: - Custom Units (only when Custom is selected)
            if userSettings.settings.unitPreferences.isCustom {
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
                    Text("Custom Units")
                } footer: {
                    Text("Pick a unit for each dimension. Weight and some other fields follow your Distance choice (mi \u{2192} lbs, km \u{2192} kg).")
                }
            }

            // Reset button only appears while in Custom mode. Imperial and
            // Metric users don't see a reset that would flip them to the other
            // clean system (which was previously aggressive).
            if userSettings.settings.unitPreferences.isCustom {
                Section {
                    Button("Reset Units to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Units", preset: userSettings.activePresetName)
        .confirmationDialog(
            "Reset Units to Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                userSettings.settings.unitPreferences = .default
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Units will be restored to Imperial.")
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
}
