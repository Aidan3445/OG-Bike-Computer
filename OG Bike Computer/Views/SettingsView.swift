//
//  SettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import SafariServices
import SwiftUI

struct SettingsView: View {
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showSupportSafari = false

    private var navigationAlertsSummary: String {
        let alerts = userSettings.settings.navigationAlerts
        let mode = alerts.turnAlerts.defaultMode
        var parts: [String] = [mode.label]
        if alerts.splitAlerts.enabled { parts.append("Splits") }
        if alerts.descentAlerts.enabled { parts.append("Descent") }
        if alerts.climbAlerts.enabled { parts.append("Climb") }
        return parts.joined(separator: " \u{2022} ")
    }

    private var rideSettingsSummary: String {
        let ride = userSettings.settings.ridePreferences
        var parts: [String] = []
        parts.append(
            ride.autoPause.enabled ? "Auto-Pause On" : "Auto-Pause Off"
        )
        parts.append("GPS \(ride.gpsAccuracyFloor.label)")
        parts.append(ride.mapRotation.label)
        return parts.joined(separator: " \u{2022} ")
    }

    var body: some View {
        List {
            // MARK: - Metric Pages
            Section {
                NavigationLink {
                    MetricCustomizationView(metricConfig: metricConfig)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Metric Pages")
                            Text(
                                "\(metricConfig.config.pages.count) pages configured"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "gauge.with.dots.needle.33percent")
                            .foregroundStyle(.blue)
                    }
                }

                // MARK: - Rider Profile
                Section {
                    NavigationLink {
                        RiderProfileView(userSettings: userSettings)
                    } label: {
                        Label {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Rider Profile")
                                Text(
                                    "\(String(format: "%.0f", userSettings.settings.riderWeight * 2.20462)) lbs \u{2022} \(userSettings.settings.activeBikeName) (\(String(format: "%.0f", userSettings.settings.bikeWeight * 2.20462)) lbs)"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "figure.outdoor.cycle")
                                .foregroundStyle(.green)
                        }
                    }
                }

                // MARK: - Units
                NavigationLink {
                    UnitsSettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Units")
                            Text(
                                userSettings.settings.unitPreferences.system?
                                    .label ?? "Custom"
                            )
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "ruler")
                            .foregroundStyle(.orange)
                    }
                }

                // MARK: - Navigation Alerts
                NavigationLink {
                    NavigationAlertSettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Navigation Alerts")
                            Text(navigationAlertsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bell.badge")
                            .foregroundStyle(.red)
                    }
                }

                // MARK: - Ride Settings
                NavigationLink {
                    RideSettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Ride Settings")
                            Text(rideSettingsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bicycle")
                            .foregroundStyle(.indigo)
                    }
                }
            }

            // MARK: - App Experience
            Section {
                NavigationLink {
                    PlaceholderSettingView(
                        title: "Color Scheme",
                        icon: "paintpalette",
                        description:
                            "Customize primary, secondary, and accent colors. The background always stays black for visibility, but you can personalize the text, icons, and highlights throughout the app."
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Color Scheme")
                            Text("Default")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "paintpalette")
                            .foregroundStyle(.purple)
                    }
                }

                NavigationLink {
                    PlaceholderSettingView(
                        title: "Map Style",
                        icon: "map",
                        description:
                            "Choose between standard, satellite, and hybrid map styles. Configure the default zoom level, whether to show traffic, and route line color preferences."
                    )
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Map Style")
                            Text("Standard")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "map")
                            .foregroundStyle(.teal)
                    }
                }

                NavigationLink {
                    PlaceholderSettingView(
                        title: "Data & Privacy",
                        icon: "lock.shield",
                        description:
                            "Manage ride data storage, export all rides, clear history, and configure what health data is recorded during workouts."
                    )
                } label: {
                    Label {
                        Text("Data & Privacy")
                    } icon: {
                        Image(systemName: "lock.shield")
                            .foregroundStyle(.gray)
                    }
                }
            } header: {
                Text("App Experience")
            }

            // MARK: - Battery Tips
            Section {
                DisclosureGroup {
                    batteryTipRow(
                        title: "GPS Accuracy",
                        value: userSettings.settings.ridePreferences
                            .gpsAccuracyFloor.label,
                        impact: userSettings.settings.ridePreferences
                            .gpsAccuracyFloor.batteryImpact,
                        instruction: "Change in Ride Settings above."
                    )
                    batteryTipRow(
                        title: "Screen Brightness",
                        value: nil,
                        impact: "Varies",
                        instruction:
                            "Adjust on Watch via Settings \u{2192} Display & Brightness."
                    )
                    batteryTipRow(
                        title: "Screen Timeout",
                        value: nil,
                        impact: "Varies",
                        instruction:
                            "Adjust on Watch via Settings \u{2192} Display & Brightness."
                    )
                    batteryTipRow(
                        title: "Always-On Display",
                        value: nil,
                        impact: "Moderate",
                        instruction:
                            "Adjust on Watch via Settings \u{2192} Display & Brightness."
                    )
                    if userSettings.settings.phoneAlerts.mode != .off {
                        batteryTipRow(
                            title: "Phone Alerts",
                            value: userSettings.settings.phoneAlerts.mode.label,
                            impact: "High",
                            instruction:
                                "Change in Ride Settings \u{2192} Phone Alerts."
                        )
                    }
                } label: {
                    Label {
                        Text("Battery Tips")
                    } icon: {
                        Image(systemName: "battery.100.bolt")
                            .foregroundStyle(.green)
                    }
                }
            } footer: {
                Text(
                    "Use Balanced GPS and lower screen brightness on long rides to extend battery life."
                )
            }

            // MARK: - Support the Developer
            Section {
                Button {
                    showSupportSafari = true
                } label: {
                    VStack(alignment: .leading, spacing: 8) {
                        HStack(spacing: 8) {
                            Image(systemName: "heart")
                                .foregroundStyle(.pink)
                            Text("Support the Developer")
                                .font(.body.weight(.semibold))
                                .foregroundStyle(.primary)
                        }

                        Text(
                            "This app is completely free. If you'd like, you can leave a voluntary tip to support the developer. Tipping is optional and does not unlock any features or affect how the app works."
                        )
                        .font(.footnote)
                        .foregroundStyle(.white)

                        HStack(spacing: 4) {
                            Text("Buy me a coffee")
                                .font(.subheadline.weight(.medium))
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                        }
                        .foregroundStyle(.blue)
                    }
                    .padding(.vertical, 4)
                }
            }
        }
        .sheet(isPresented: $showSupportSafari) {
            SafariView(
                url: URL(string: "https://www.buymeacoffee.com/aidanweinberg")!
            )
        }
        .navigationTitle("Settings")
    }

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

// MARK: - Rider Profile

struct RiderProfileView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showAddBike = false
    @State private var newBikeName = ""
    @State private var newBikeWeight = "22"  // lbs

    // Imperial bindings (stored as kg/cm, displayed as lbs/in)
    private var riderWeightLbs: Binding<Double> {
        Binding(
            get: { userSettings.settings.riderWeight * 2.20462 },
            set: { userSettings.settings.riderWeight = $0 / 2.20462 }
        )
    }

    private var riderHeightIn: Binding<Double> {
        Binding(
            get: { userSettings.settings.riderHeight / 2.54 },
            set: { userSettings.settings.riderHeight = $0 * 2.54 }
        )
    }

    private func bikeWeightLbs(at index: Int) -> Binding<Double> {
        Binding(
            get: { userSettings.settings.bikes[index].weight * 2.20462 },
            set: { userSettings.settings.bikes[index].weight = $0 / 2.20462 }
        )
    }

    private var heightString: String {
        let totalInches = userSettings.settings.riderHeight / 2.54
        let feet = Int(totalInches) / 12
        let inches = Int(totalInches) % 12
        return "\(feet)'\(inches)\""
    }

    var body: some View {
        Form {
            // MARK: Rider
            Section {
                HStack {
                    Label("Weight", systemImage: "scalemass")
                    Spacer()
                    TextField(
                        "lbs",
                        value: riderWeightLbs,
                        format: .number.precision(.fractionLength(0))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("lbs")
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Height", systemImage: "ruler")
                    Spacer()
                    TextField(
                        "in",
                        value: riderHeightIn,
                        format: .number.precision(.fractionLength(0))
                    )
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                    Text("in")
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Rider")
            } footer: {
                Text(
                    "\(String(format: "%.0f", userSettings.settings.riderWeight * 2.20462)) lbs \u{2022} \(heightString)"
                )
            }

            // MARK: Bikes
            Section {
                ForEach(userSettings.settings.bikes) { bike in
                    let isActive = userSettings.settings.activeBikeID == bike.id
                    Button {
                        userSettings.settings.activeBikeID = bike.id
                    } label: {
                        HStack(spacing: 12) {
                            Image(
                                systemName: isActive
                                    ? "checkmark.circle.fill" : "circle"
                            )
                            .foregroundStyle(isActive ? .green : .secondary)
                            .font(.title3)

                            VStack(alignment: .leading, spacing: 2) {
                                Text(bike.name)
                                    .font(.body)
                                    .foregroundStyle(.primary)
                                Text(
                                    "\(String(format: "%.1f", bike.weight * 2.20462)) lbs"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }

                            Spacer()

                            if isActive {
                                Text("Active")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
                .onDelete { indices in
                    let wasActive = indices.contains(where: {
                        userSettings.settings.bikes[$0].id
                            == userSettings.settings.activeBikeID
                    })
                    userSettings.settings.bikes.remove(atOffsets: indices)
                    if wasActive, let first = userSettings.settings.bikes.first
                    {
                        userSettings.settings.activeBikeID = first.id
                    }
                }
            } header: {
                HStack {
                    Text("Bikes")
                    Spacer()
                    Button {
                        showAddBike = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .font(.body)
                    }
                }
            } footer: {
                Text(
                    "Tap to select the active bike. Its weight is used for power estimation. Swipe to delete."
                )
            }

            // MARK: Bike Editor (inline for active bike)
            if let activeIdx = userSettings.settings.bikes.firstIndex(where: {
                $0.id == userSettings.settings.activeBikeID
            }) {
                Section {
                    HStack {
                        Label("Name", systemImage: "pencil")
                        Spacer()
                        TextField(
                            "Bike name",
                            text: $userSettings.settings.bikes[activeIdx].name
                        )
                        .multilineTextAlignment(.trailing)
                    }
                    HStack {
                        Label("Weight", systemImage: "scalemass")
                        Spacer()
                        TextField(
                            "lbs",
                            value: bikeWeightLbs(at: activeIdx),
                            format: .number.precision(.fractionLength(1))
                        )
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        Text("lbs")
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text(
                        "Edit \"\(userSettings.settings.bikes[activeIdx].name)\""
                    )
                }
            }

            // MARK: Summary
            Section {
                HStack {
                    Text("Total Weight")
                        .fontWeight(.medium)
                    Spacer()
                    Text(
                        "\(String(format: "%.0f", userSettings.settings.totalMass * 2.20462)) lbs"
                    )
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    "Power estimation uses total rider + bike weight. Heavier setups require more watts at the same speed and grade. Changes sync to the watch live."
                )
            }
        }
        .navigationTitle("Rider Profile")
        .alert("Add Bike", isPresented: $showAddBike) {
            TextField("Name (e.g. Road Bike)", text: $newBikeName)
            TextField("Weight in lbs", text: $newBikeWeight)
                .keyboardType(.decimalPad)
            Button("Add") {
                let name =
                    newBikeName.isEmpty
                    ? "Bike \(userSettings.settings.bikes.count + 1)"
                    : newBikeName
                let lbs = Double(newBikeWeight) ?? 22
                let bike = BikePreset(name: name, weight: lbs / 2.20462)  // store as kg
                userSettings.settings.bikes.append(bike)
                if userSettings.settings.bikes.count == 1 {
                    userSettings.settings.activeBikeID = bike.id
                }
                newBikeName = ""
                newBikeWeight = "22"
            }
            Button("Cancel", role: .cancel) {
                newBikeName = ""
                newBikeWeight = "22"
            }
        }
    }
}

// MARK: - Safari View

struct SafariView: UIViewControllerRepresentable {
    let url: URL

    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }

    func updateUIViewController(
        _ uiViewController: SFSafariViewController,
        context: Context
    ) {}
}

// MARK: - Placeholder Setting

struct PlaceholderSettingView: View {
    let title: String
    let icon: String
    let description: String

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Coming Soon")
                .font(.title2.weight(.semibold))
            Text(description)
                .font(.body)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
            Spacer()
            Spacer()
        }
        .navigationTitle(title)
    }
}
