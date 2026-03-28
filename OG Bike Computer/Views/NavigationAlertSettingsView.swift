//
//  NavigationAlertSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

// MARK: - Wheel Picker Options

/// Generates an array of (label, meters) tuples for distance wheel pickers.
/// Handles the ft→mi and m→km transition with unit labels changing mid-scroll.
private func distanceOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, meters: Double)] {
    var options: [(String, Double)] = []

    if isImperial {
        let minFt = min * 3.28084
        let maxFt = max * 3.28084

        // Feet range: 50ft steps up to 1000ft
        let ftStart = Swift.max(50, Int((minFt / 50).rounded(.up)) * 50)
        let ftEnd = Swift.min(1000, Int((maxFt / 50).rounded(.down)) * 50)
        if ftStart <= ftEnd {
            for ft in stride(from: ftStart, through: ftEnd, by: 50) {
                options.append(("\(ft) ft", Double(ft) / 3.28084))
            }
        }

        // Miles range: 0.05mi steps
        let minMi = min / 1609.34
        let maxMi = max / 1609.34
        let miStart = Swift.max(0.1, (minMi * 20).rounded(.up) / 20)
        let miEnd = (maxMi * 20).rounded(.down) / 20

        if miStart <= miEnd {
            var mi = miStart
            while mi <= miEnd + 0.001 {
                // Skip miles that overlap with feet range
                let asFt = mi * 5280
                if asFt > 1000 || options.isEmpty {
                    if mi < 1 {
                        options.append((String(format: "%.2f mi", mi), mi * 1609.34))
                    } else {
                        options.append((String(format: "%.1f mi", mi), mi * 1609.34))
                    }
                }
                mi += 0.05
            }
        }
    } else {
        let minM = min
        let maxM = max

        // Meters range: 25m steps up to 1000m
        let mStart = Swift.max(25, Int((minM / 25).rounded(.up)) * 25)
        let mEnd = Swift.min(1000, Int((maxM / 25).rounded(.down)) * 25)
        if mStart <= mEnd {
            for m in stride(from: mStart, through: mEnd, by: 25) {
                options.append(("\(m) m", Double(m)))
            }
        }

        // Km range: 0.1km steps
        let minKm = min / 1000
        let maxKm = max / 1000
        let kmStart = Swift.max(0.1, (minKm * 10).rounded(.up) / 10)
        let kmEnd = (maxKm * 10).rounded(.down) / 10

        if kmStart <= kmEnd {
            var km = kmStart
            while km <= kmEnd + 0.001 {
                let asM = km * 1000
                if asM > 1000 || options.isEmpty {
                    options.append((String(format: "%.1f km", km), km * 1000))
                }
                km += 0.1
            }
        }
    }

    return options
}

private func speedOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, mps: Double)] {
    var options: [(String, Double)] = []
    if isImperial {
        // mph, 5mph steps
        let minMph = Int((min * 2.23694 / 5).rounded(.up)) * 5
        let maxMph = Int((max * 2.23694 / 5).rounded(.down)) * 5
        for mph in stride(from: Swift.max(5, minMph), through: maxMph, by: 5) {
            options.append(("\(mph) mph", Double(mph) / 2.23694))
        }
    } else {
        // kph, 5kph steps
        let minKph = Int((min * 3.6 / 5).rounded(.up)) * 5
        let maxKph = Int((max * 3.6 / 5).rounded(.down)) * 5
        for kph in stride(from: Swift.max(5, minKph), through: maxKph, by: 5) {
            options.append(("\(kph) km/h", Double(kph) / 3.6))
        }
    }
    return options
}

private func elevationOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, meters: Double)] {
    var options: [(String, Double)] = []
    if isImperial {
        // feet, 50ft steps
        let minFt = Int((min * 3.28084 / 50).rounded(.up)) * 50
        let maxFt = Int((max * 3.28084 / 50).rounded(.down)) * 50
        for ft in stride(from: Swift.max(50, minFt), through: maxFt, by: 50) {
            options.append(("\(ft) ft", Double(ft) / 3.28084))
        }
    } else {
        // meters, 25m steps
        let minM = Int((min / 25).rounded(.up)) * 25
        let maxM = Int((max / 25).rounded(.down)) * 25
        for m in stride(from: Swift.max(25, minM), through: maxM, by: 25) {
            options.append(("\(m) m", Double(m)))
        }
    }
    return options
}

/// Finds the closest option index for a stored meter value
private func closestIndex(for value: Double, in options: [(label: String, meters: Double)]) -> Int {
    guard !options.isEmpty else { return 0 }
    var best = 0
    var bestDiff = Double.greatestFiniteMagnitude
    for (i, opt) in options.enumerated() {
        let diff = abs(opt.meters - value)
        if diff < bestDiff {
            bestDiff = diff
            best = i
        }
    }
    return best
}

private func closestSpeedIndex(for value: Double, in options: [(label: String, mps: Double)]) -> Int {
    guard !options.isEmpty else { return 0 }
    var best = 0
    var bestDiff = Double.greatestFiniteMagnitude
    for (i, opt) in options.enumerated() {
        let diff = abs(opt.mps - value)
        if diff < bestDiff {
            bestDiff = diff
            best = i
        }
    }
    return best
}

// MARK: - Alert Mode Picker

private struct AlertModePicker: View {
    let label: String
    @Binding var mode: AlertMode

    var body: some View {
        Picker(label, selection: $mode) {
            ForEach(AlertMode.allCases, id: \.self) { mode in
                Text(mode.shortLabel).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }
}

/// Alert mode picker that supports an optional override (nil = use default)
private struct OptionalAlertModePicker: View {
    let label: String
    @Binding var mode: AlertMode?
    let defaultMode: AlertMode

    private var binding: Binding<AlertMode> {
        Binding(
            get: { mode ?? defaultMode },
            set: { newValue in
                mode = (newValue == defaultMode) ? nil : newValue
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(label)
                Spacer()
                if mode == nil {
                    Text("Default")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Picker(label, selection: binding) {
                ForEach(AlertMode.allCases, id: \.self) { m in
                    Text(m.shortLabel).tag(m)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

// MARK: - Distance Picker

private struct DistancePicker: View {
    let label: String
    @Binding var meters: Double
    let min: Double
    let max: Double

    var body: some View {
        let isImperial = currentUnits.distance == .miles
        let options = distanceOptions(min: min, max: max, isImperial: isImperial)
        guard !options.isEmpty else { return AnyView(EmptyView()) }

        let binding = Binding<Int>(
            get: { closestIndex(for: meters, in: options) },
            set: { meters = options[$0].meters }
        )

        return AnyView(
            Picker(label, selection: binding) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i].label).tag(i)
                }
            }
        )
    }
}

private struct SpeedPicker: View {
    let label: String
    @Binding var mps: Double
    let min: Double // m/s
    let max: Double // m/s

    var body: some View {
        let isImperial = currentUnits.speed == .mph
        let options = speedOptions(min: min, max: max, isImperial: isImperial)
        guard !options.isEmpty else { return AnyView(EmptyView()) }

        let binding = Binding<Int>(
            get: { closestSpeedIndex(for: mps, in: options) },
            set: { mps = options[$0].mps }
        )

        return AnyView(
            Picker(label, selection: binding) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i].label).tag(i)
                }
            }
        )
    }
}

private struct ElevationPicker: View {
    let label: String
    @Binding var meters: Double
    let min: Double
    let max: Double

    var body: some View {
        let isImperial = currentUnits.elevation == .feet
        let options = elevationOptions(min: min, max: max, isImperial: isImperial)
        guard !options.isEmpty else { return AnyView(EmptyView()) }

        let binding = Binding<Int>(
            get: { closestIndex(for: meters, in: options) },
            set: { meters = options[$0].meters }
        )

        return AnyView(
            Picker(label, selection: binding) {
                ForEach(0..<options.count, id: \.self) { i in
                    Text(options[i].label).tag(i)
                }
            }
        )
    }
}

// MARK: - Split Distance Picker

private struct SplitDistancePicker: View {
    @Binding var meters: Double

    private var options: [(label: String, meters: Double)] {
        let isImperial = currentUnits.distance == .miles
        if isImperial {
            return [
                ("0.25 mi", 0.25 * 1609.34),
                ("0.5 mi", 0.5 * 1609.34),
                ("1 mi", 1609.34),
                ("2 mi", 2 * 1609.34),
                ("5 mi", 5 * 1609.34),
                ("10 mi", 10 * 1609.34),
            ]
        } else {
            return [
                ("0.5 km", 500),
                ("1 km", 1000),
                ("2 km", 2000),
                ("5 km", 5000),
                ("10 km", 10000),
            ]
        }
    }

    var body: some View {
        let opts = options
        let binding = Binding<Int>(
            get: { closestIndex(for: meters, in: opts) },
            set: { meters = opts[$0].meters }
        )

        Picker("Split Distance", selection: binding) {
            ForEach(0..<opts.count, id: \.self) { i in
                Text(opts[i].label).tag(i)
            }
        }
    }
}

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
        }
        .navigationTitle("Navigation Alerts")
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
                    SplitMetricPickerView(selectedMetrics: prefs.splitAlerts.selectedMetrics)
                } label: {
                    HStack {
                        Text("Stats to Read")
                        Spacer()
                        Text("\(userSettings.settings.navigationAlerts.splitAlerts.selectedMetrics.count) selected")
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
