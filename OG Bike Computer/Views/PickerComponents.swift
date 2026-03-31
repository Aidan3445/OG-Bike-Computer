//
//  PickerComponents.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

// MARK: - Option Generators

/// Generates (label, meters) tuples for distance pickers with ft→mi / m→km transitions.
func distanceOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, meters: Double)] {
    var options: [(String, Double)] = []

    if isImperial {
        let minFt = min * 3.28084
        let maxFt = max * 3.28084

        let ftStart = Swift.max(50, Int((minFt / 50).rounded(.up)) * 50)
        let ftEnd = Swift.min(1000, Int((maxFt / 50).rounded(.down)) * 50)
        if ftStart <= ftEnd {
            for ft in stride(from: ftStart, through: ftEnd, by: 50) {
                options.append(("\(ft) ft", Double(ft) / 3.28084))
            }
        }

        let minMi = min / 1609.34
        let maxMi = max / 1609.34
        let miStart = Swift.max(0.1, (minMi * 20).rounded(.up) / 20)
        let miEnd = (maxMi * 20).rounded(.down) / 20

        if miStart <= miEnd {
            var mi = miStart
            while mi <= miEnd + 0.001 {
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

        let mStart = Swift.max(25, Int((minM / 25).rounded(.up)) * 25)
        let mEnd = Swift.min(1000, Int((maxM / 25).rounded(.down)) * 25)
        if mStart <= mEnd {
            for m in stride(from: mStart, through: mEnd, by: 25) {
                options.append(("\(m) m", Double(m)))
            }
        }

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

func speedOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, mps: Double)] {
    var options: [(String, Double)] = []
    if isImperial {
        let minMph = Int((min * 2.23694 / 5).rounded(.up)) * 5
        let maxMph = Int((max * 2.23694 / 5).rounded(.down)) * 5
        for mph in stride(from: Swift.max(5, minMph), through: maxMph, by: 5) {
            options.append(("\(mph) mph", Double(mph) / 2.23694))
        }
    } else {
        let minKph = Int((min * 3.6 / 5).rounded(.up)) * 5
        let maxKph = Int((max * 3.6 / 5).rounded(.down)) * 5
        for kph in stride(from: Swift.max(5, minKph), through: maxKph, by: 5) {
            options.append(("\(kph) km/h", Double(kph) / 3.6))
        }
    }
    return options
}

func elevationOptions(min: Double, max: Double, isImperial: Bool) -> [(label: String, meters: Double)] {
    var options: [(String, Double)] = []
    if isImperial {
        let minFt = Int((min * 3.28084 / 50).rounded(.up)) * 50
        let maxFt = Int((max * 3.28084 / 50).rounded(.down)) * 50
        for ft in stride(from: Swift.max(50, minFt), through: maxFt, by: 50) {
            options.append(("\(ft) ft", Double(ft) / 3.28084))
        }
    } else {
        let minM = Int((min / 25).rounded(.up)) * 25
        let maxM = Int((max / 25).rounded(.down)) * 25
        for m in stride(from: Swift.max(25, minM), through: maxM, by: 25) {
            options.append(("\(m) m", Double(m)))
        }
    }
    return options
}

/// Finds the closest option index for a stored meter value
func closestIndex(for value: Double, in options: [(label: String, meters: Double)]) -> Int {
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

func closestSpeedIndex(for value: Double, in options: [(label: String, mps: Double)]) -> Int {
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

// MARK: - Picker Views

struct AlertModePicker: View {
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

struct OptionalAlertModePicker: View {
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

struct DistancePicker: View {
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

struct SpeedPicker: View {
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

struct ElevationPicker: View {
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

struct SplitDistancePicker: View {
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

// MARK: - Auto-Pause Speed Picker

struct PauseSpeedPicker: View {
    @Binding var mps: Double

    private var options: [(label: String, mps: Double)] {
        let isImperial = currentUnits.speed == .mph
        if isImperial {
            // 1-5 mph in 0.5 steps
            return stride(from: 1.0, through: 5.0, by: 0.5).map { mph in
                (String(format: "%.1f mph", mph), mph / 2.23694)
            }
        } else {
            // 1-8 km/h in 1 step
            return stride(from: 1, through: 8, by: 1).map { kph in
                ("\(kph) km/h", Double(kph) / 3.6)
            }
        }
    }

    var body: some View {
        let opts = options
        let binding = Binding<Int>(
            get: { closestSpeedIndex(for: mps, in: opts) },
            set: { mps = opts[$0].mps }
        )

        Picker("Pause Speed", selection: binding) {
            ForEach(0..<opts.count, id: \.self) { i in
                Text(opts[i].label).tag(i)
            }
        }
    }
}
