//
//  SettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import SafariServices
import SwiftUI

// MARK: - Unit-Aware Formatting Helpers

private func zoomLabel(_ meters: Double) -> String {
    if currentUnits.distance == .miles {
        let feet = meters * 3.28084
        if feet >= 2640 {
            let miles = meters / 1609.34
            if miles == Double(Int(miles)) { return "\(Int(miles)) mi" }
            return String(format: "%.1f mi", miles)
        }
        return "\(Int(round(feet))) ft"
    }
    return "\(Int(meters))m"
}

private func weightLabel(_ kg: Double) -> String {
    if currentUnits.distance == .miles {
        return "\(String(format: "%.0f", kg * 2.20462)) lbs"
    }
    return "\(String(format: "%.1f", kg)) kg"
}

struct SettingsView: View {
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var integrationSettings: IntegrationSettingsStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject var routeStore: RouteStore
    @State private var showSupportSafari = false
    @State private var showClearRides = false
    @State private var showClearRoutes = false
    @StateObject private var connectivity = ConnectivityManager.shared

    private var navigationAlertsSummary: String {
        let alerts = userSettings.settings.navigationAlerts
        let mode = alerts.turnAlerts.defaultMode
        var parts: [String] = [mode.label]
        if alerts.splitAlerts.enabled { parts.append("Splits") }
        if alerts.descentAlerts.enabled { parts.append("Descent") }
        if alerts.climbAlerts.enabled { parts.append("Climb") }
        return parts.joined(separator: " \u{2022} ")
    }

    private var integrationsSummary: String {
        let connected = integrationSettings.settings.connectedServices
        if connected.isEmpty {
            return "No services connected"
        }
        return connected.map(\.displayName).joined(separator: ", ")
    }

    private var mapScreenSummary: String {
        let map = userSettings.settings.ridePreferences.mapScreen
        var parts: [String] = []
        if map.mapDetail != .off { parts.append(map.mapDetail.label) }
        parts.append(map.routeAheadColor.label)
        parts.append("\(zoomLabel(map.defaultZoom)) zoom")
        if !map.showTurnOverlay { parts.append("Overlay off") }
        return parts.joined(separator: " \u{2022} ")
    }

    private var isImperial: Bool { currentUnits.distance == .miles }

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
                    MapCustomizationView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Map Screen")
                            Text(mapScreenSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "map")
                            .foregroundStyle(.blue)
                    }
                }
                
                NavigationLink {
                    MetricCustomizationView(metricConfig: metricConfig, userSettings: userSettings, profileName: userSettings.activeProfileName)
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
                            .foregroundStyle(.yellow)
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
                                    "\(weightLabel(userSettings.settings.riderWeight)) \u{2022} \(userSettings.settings.activeBikeName) (\(weightLabel(userSettings.settings.bikeWeight)))"
                                )
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            }
                        } icon: {
                            Image(systemName: "figure.outdoor.cycle")
                                .foregroundStyle(.purple)
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
                        Image(systemName: "bicycle.circle")
                            .foregroundStyle(.indigo)
                    }
                }
                
                // MARK: - Battery & Efficiency
                NavigationLink {
                    BatterySettingsView(userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Battery & Efficiency")
                            Text("Optimize for daily riding or touring")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "battery.100.bolt")
                            .foregroundStyle(.green)
                    }
                }
            }

            // MARK: - Integrations
            Section {
                NavigationLink {
                    IntegrationsSettingsView(integrationSettings: integrationSettings, userSettings: userSettings)
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Integrations")
                            Text(integrationsSummary)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.triangle.2.circlepath")
                            .foregroundStyle(.teal)
                    }
                }
            }

            // MARK: - Data Management
            Section {
                Button(role: .destructive) {
                    showClearRoutes = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear All Routes")
                            Text("\($routeStore.routes.count) routes on phone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            Text("\(connectivity.routeNamesOnWatch.count) routes on watch")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "point.topleft.down.to.point.bottomright.curvepath.fill")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(routeStore.routes.isEmpty)
                
                Button(role: .destructive) {
                    showClearRides = true
                } label: {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Clear All Rides")
                            Text("\(rideStore.rides.count) rides on phone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "bicycle")
                            .foregroundStyle(.red)
                    }
                }
                .disabled(rideStore.rides.isEmpty)
            } header: {
                Text("Data Management")
            } footer: {
                // MARK: - App Version
                let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
                let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"

                let versionString = "Version \(version) (\(build))"
                Text(versionString)
                    .font(.footnote)
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
            }

//            // MARK: - Support the Developer
//            Section {
//                Button {
//                    showSupportSafari = true
//                } label: {
//                    VStack(alignment: .leading, spacing: 8) {
//                        HStack(spacing: 8) {
//                            Image(systemName: "heart")
//                                .foregroundStyle(.pink)
//                            Text("Support the Developer")
//                                .font(.body.weight(.semibold))
//                                .foregroundStyle(.primary)
//                        }
//
//                        Text(
//                            "This app is completely free. If you'd like, you can leave a voluntary tip to support the developer. Tipping is optional and does not unlock any features or affect how the app works."
//                        )
//                        .font(.footnote)
//                        .foregroundStyle(.white)
//
//                        HStack(spacing: 4) {
//                            Text("Buy me a coffee")
//                                .font(.subheadline.weight(.medium))
//                            Image(systemName: "arrow.up.right")
//                                .font(.caption)
//                        }
//                        .foregroundStyle(.blue)
//                    }
//                    .padding(.vertical, 4)
//                }
//            }
        }
//        .sheet(isPresented: $showSupportSafari) {
//            SafariView(
//                url: URL(string: "https://www.buymeacoffee.com/aidanweinberg")!
//            )
//        }
        .sheet(isPresented: $showClearRoutes) {
            ClearRoutesSheet(
                phoneRouteCount: $routeStore.routes.count,
                watchRouteCount: connectivity.routeNamesOnWatch.count,
                onConfirm: { alsoWatch in
                    routeStore.deleteAll()
                    if alsoWatch {
                        connectivity.sendClearAllRoutes()
                    }
                }
            )
            .presentationDetents([.height(280)])
        }
        .sheet(isPresented: $showClearRides) {
            ClearRidesSheet(
                rideCount: rideStore.rides.count,
                onConfirm: {
                    rideStore.deleteAll()
                }
            )
            .presentationDetents([.height(280)])
        }
        .settingsPageTitle("Settings", profile: userSettings.activeProfileName)
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

// MARK: - Rider Profile

struct RiderProfileView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showAddBike = false
    @State private var newBikeName = ""
    @State private var newBikeWeight = ""
    @State private var weightText = ""
    @State private var heightText = ""
    @State private var bikeWeightText = ""
    @FocusState private var isFieldFocused: Bool

    private var isImperial: Bool { currentUnits.distance == .miles }

    private var heightString: String {
        if isImperial {
            let totalInches = userSettings.settings.riderHeight / 2.54
            let feet = Int(totalInches) / 12
            let inches = Int(totalInches) % 12
            return "\(feet)'\(inches)\""
        } else {
            return "\(Int(round(userSettings.settings.riderHeight))) cm"
        }
    }

    private var weightUnit: String { isImperial ? "lbs" : "kg" }
    private var heightUnit: String { isImperial ? "in" : "cm" }

    private func kgToDisplay(_ kg: Double) -> String {
        if isImperial {
            return "\(Int(round(kg * 2.20462)))"
        }
        return String(format: "%.1f", kg)
    }

    private func displayToKg(_ value: Double) -> Double {
        isImperial ? value / 2.20462 : value
    }

    private func cmToDisplay(_ cm: Double) -> String {
        if isImperial {
            return "\(Int(round(cm / 2.54)))"
        }
        return "\(Int(round(cm)))"
    }

    private func displayToCm(_ value: Double) -> Double {
        isImperial ? value * 2.54 : value
    }

    var body: some View {
        Form {
            // MARK: Rider
            Section {
                HStack {
                    Label("Weight", systemImage: "scalemass")
                    Spacer()
                    TextField(weightUnit, text: $weightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($isFieldFocused)
                        .onChange(of: weightText) { _, newValue in
                            if let val = Double(newValue) {
                                userSettings.settings.riderWeight = displayToKg(val)
                            }
                        }
                    Text(weightUnit)
                        .foregroundStyle(.secondary)
                }
                HStack {
                    Label("Height", systemImage: "ruler")
                    Spacer()
                    TextField(heightUnit, text: $heightText)
                        .keyboardType(.decimalPad)
                        .multilineTextAlignment(.trailing)
                        .frame(width: 80)
                        .focused($isFieldFocused)
                        .onChange(of: heightText) { _, newValue in
                            if let val = Double(newValue) {
                                userSettings.settings.riderHeight = displayToCm(val)
                            }
                        }
                    Text(heightUnit)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Rider")
            } footer: {
                Text(
                    "\(weightLabel(userSettings.settings.riderWeight)) \u{2022} \(heightString)"
                )
            }
            .onAppear {
                weightText = kgToDisplay(userSettings.settings.riderWeight)
                heightText = cmToDisplay(userSettings.settings.riderHeight)
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
                                Text(weightLabel(bike.weight))
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
                        .focused($isFieldFocused)
                    }
                    HStack {
                        Label("Weight", systemImage: "scalemass")
                        Spacer()
                        TextField(weightUnit, text: $bikeWeightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                            .focused($isFieldFocused)
                            .onChange(of: bikeWeightText) { _, newValue in
                                if let val = Double(newValue) {
                                    userSettings.settings.bikes[activeIdx].weight = displayToKg(val)
                                }
                            }
                        Text(weightUnit)
                            .foregroundStyle(.secondary)
                    }
                    .onAppear {
                        bikeWeightText = kgToDisplay(userSettings.settings.bikes[activeIdx].weight)
                    }
                    .onChange(of: userSettings.settings.activeBikeID) { _, _ in
                        if let idx = userSettings.settings.bikes.firstIndex(where: { $0.id == userSettings.settings.activeBikeID }) {
                            bikeWeightText = kgToDisplay(userSettings.settings.bikes[idx].weight)
                        }
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
                    Text(weightLabel(userSettings.settings.totalMass))
                    .foregroundStyle(.secondary)
                }
            } footer: {
                Text(
                    "Power estimation uses total rider + bike weight. Heavier setups require more watts at the same speed and grade. Changes sync to the watch live."
                )
            }
        }
        .settingsPageTitle("Rider Profile", profile: userSettings.activeProfileName)
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("Done") { isFieldFocused = false }
            }
        }
        .alert("Add Bike", isPresented: $showAddBike) {
            TextField("Name (e.g. Road Bike)", text: $newBikeName)
            TextField("Weight in \(weightUnit)", text: $newBikeWeight)
                .keyboardType(.decimalPad)
            Button("Add") {
                let name =
                    newBikeName.isEmpty
                    ? "Bike \(userSettings.settings.bikes.count + 1)"
                    : newBikeName
                let val = Double(newBikeWeight) ?? (isImperial ? 22 : 10)
                let bike = BikePreset(name: name, weight: displayToKg(val))
                userSettings.settings.bikes.append(bike)
                if userSettings.settings.bikes.count == 1 {
                    userSettings.settings.activeBikeID = bike.id
                }
                newBikeName = ""
                newBikeWeight = ""
            }
            Button("Cancel", role: .cancel) {
                newBikeName = ""
                newBikeWeight = ""
            }
        }
    }
}

// MARK: - Clear Routes Sheet

struct ClearRoutesSheet: View {
    let phoneRouteCount: Int
    let watchRouteCount: Int
    let onConfirm: (Bool) -> Void
    @State private var deleteFromPhone = false
    @State private var deleteFromWatch = false
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 36))
                    .foregroundStyle(.red)

                Text("Delete all \((deleteFromPhone ? phoneRouteCount : 0) + (deleteFromWatch ? watchRouteCount : 0)) routes?")
                    .font(.headline)

                Text("This will permanently delete all routes from your phone. This cannot be undone.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                Toggle(isOn: $deleteFromPhone) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete from phone")
                        Text("Removes all routes on this device")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .disabled(phoneRouteCount == 0)
                
                Toggle(isOn: $deleteFromWatch) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Delete from watch")
                        Text("Removes all routes synced to your Apple Watch")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal)
                .disabled(watchRouteCount == 0)

                .safeAreaInset(edge: .bottom) {
                    Button(role: .destructive) {
                        onConfirm(deleteFromWatch)
                        dismiss()
                    } label: {
                        let targets: [String] = [
                            deleteFromPhone ? "Phone" : nil,
                            deleteFromWatch ? "Watch" : nil
                        ].compactMap { $0 }
                        let deleteText = targets.count == 0
                            ? "Select devices"
                            : "Delete from \(targets.joined(separator: " & "))"
                            
                        Text(deleteText)
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.red)
                    .padding(.horizontal)
                    .padding(.bottom, 20)
                    .disabled(!(deleteFromPhone || deleteFromWatch))
                }
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Clear Rides Sheet
struct ClearRidesSheet: View {
    let rideCount: Int
    let onConfirm: () -> Void

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 16) {

            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.red)

            Text("Delete all \(rideCount) rides?")
                .font(.headline)
                .multilineTextAlignment(.center)

            Text("This will permanently delete all ride history from your phone. This cannot be undone.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)

            Spacer()

            Button(role: .destructive) {
                onConfirm()
                dismiss()
            } label: {
                Text("Delete All Rides")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") { dismiss() }
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

// MARK: - Settings Profile Subtitle

extension View {
    func settingsPageTitle(_ title: String, profile: String) -> some View {
        self
            .navigationTitle(title)
            .navigationSubtitle(profile)
    }
}

