//
//  BatterySettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI

struct BatterySettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var metricConfig: MetricConfigStore

    var body: some View {
        Form {
            // MARK: - Current Impact
            Section {
                batteryTipRow(
                    title: "GPS Accuracy",
                    value: userSettings.settings.ridePreferences
                        .gpsAccuracyFloor.label,
                    impact: userSettings.settings.ridePreferences
                        .gpsAccuracyFloor.batteryImpact,
                    instruction: "Change in Ride Settings."
                )
                batteryTipRow(
                    title: "Live Activity Updates",
                    value: userSettings.settings.ridePreferences.telemetryRate.label,
                    impact: userSettings.settings.ridePreferences.telemetryRate.batteryImpact,
                    instruction: "Change below in Efficiency Settings."
                )
                batteryTipRow(
                    title: "Map Detail",
                    value: userSettings.settings.ridePreferences.mapScreen.mapDetail.label,
                    impact: userSettings.settings.ridePreferences.mapScreen.mapDetail.batteryImpact,
                    instruction: "Change in Map Screen settings."
                )
                batteryTipRow(
                    title: "Display Brightness & Always-On",
                    value: nil,
                    impact: "Varies",
                    instruction:
                        "Adjust on Watch via Settings \u{2192} Display & Brightness."
                )
                if userSettings.settings.phoneAlerts.showTurnNotifications {
                    batteryTipRow(
                        title: "Turn Notifications",
                        value: "On",
                        impact: "Low",
                        instruction: "Toggle off in Live Activity settings."
                    )
                }
            } header: {
                Text("Current Impact")
            }

            // MARK: - Efficiency Settings
            Section {
                Toggle(isOn: $userSettings.settings.ridePreferences.dynamicGPSOptimization) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Dynamic GPS Optimization")
                        Text("Reduce GPS accuracy when far from turns")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Picker("Live Activity Update Rate", selection: $userSettings.settings.ridePreferences.telemetryRate) {
                    ForEach(TelemetryRate.allCases, id: \.self) { rate in
                        Text(rate.label).tag(rate)
                    }
                }

                Stepper(
                    "Off-Route Grace: \(userSettings.settings.ridePreferences.offRouteGraceSamples)s",
                    value: $userSettings.settings.ridePreferences.offRouteGraceSamples,
                    in: 1...10
                )
            } header: {
                Text("Efficiency Settings")
            } footer: {
                Text(
                    "These features improve reliability for everyday riding. Disable them to maximize battery life on long touring days."
                )
            }

            // MARK: - Related Settings
            Section {
                NavigationLink {
                    MapCustomizationView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Map Screen")
                            Text("Map background, route colors, overlays")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "map")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink {
                    RideSettingsView(userSettings: userSettings, metricConfig: metricConfig)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("GPS & Sensors")
                            Text("GPS accuracy, elevation smoothing, auto-pause")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "location.circle")
                            .foregroundStyle(.blue)
                    }
                }

                NavigationLink {
                    PhoneAlertSettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Live Activity")
                            Text("Live Activity stats and optional turn notifications")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "iphone.radiowaves.left.and.right")
                            .foregroundStyle(.orange)
                    }
                }

                NavigationLink {
                    NavigationAlertSettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alert Frequency")
                            Text("Turn alerts, splits, haptics")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.red)
                    }
                }
            } header: {
                Text("Related Settings")
            } footer: {
                Text(
                    "These settings aren't directly battery features but have a significant impact on battery life during rides."
                )
            }
        }
        .settingsPageTitle("Battery & Efficiency", profile: userSettings.activeProfileName)
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

    // MARK: - Helpers

    private func batteryTipRow(
        title: String,
        value: String?,
        impact: String,
        instruction: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                    .font(.subheadline)
                Spacer()
                if let value {
                    Text(value)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            HStack {
                Text(impact)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(impactColor(impact))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(impactColor(impact).opacity(0.15))
                    .clipShape(Capsule())
                Text(instruction)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }

    private func impactColor(_ impact: String) -> Color {
        switch impact {
        case "Most demanding", "High": return .red
        case "Moderate": return .orange
        case "Least demanding": return .green
        default: return .secondary
        }
    }
}
