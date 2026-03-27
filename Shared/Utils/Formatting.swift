//
//  Formatting.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import SwiftUI

/// Global unit preferences — set from UserSettingsStore on app launch and on changes.
var currentUnits: UnitPreferences = .default

func formatDistance(_ meters: Double, _ units: Bool = true) -> String {
    switch currentUnits.distance {
    case .miles:
        let miles = meters / 1609.34
        return String(format: "%.1f%@", miles, units ? " mi" : "")
    case .kilometers:
        let km = meters / 1000
        return String(format: "%.1f%@", km, units ? " km" : "")
    }
}

func formatTurnDistance(_ meters: Double) -> String {
    switch currentUnits.distance {
    case .miles:
        if meters >= 1609 {
            return String(format: "%.1f", meters / 1609.34)
        } else {
            let feet = Int(meters * 3.28084)
            return "\((feet / 50) * 50) ft"
        }
    case .kilometers:
        if meters >= 1000 {
            return String(format: "%.1f", meters / 1000)
        } else {
            let m = Int(meters)
            return "\((m / 50) * 50) m"
        }
    }
}

func formatElevation(_ meters: Double) -> String {
    switch currentUnits.elevation {
    case .feet:
        let feet = meters * 3.28084
        return String(format: "%.0f ft", feet)
    case .meters:
        return String(format: "%.0f m", meters)
    }
}

func formatSpeed(_ metersPerSecond: Double, _ units: Bool = true) -> String {
    switch currentUnits.speed {
    case .mph:
        let mph = metersPerSecond * 2.23694
        return String(format: "%.1f%@", mph, units ? " mph" : "")
    case .kmh:
        let kmh = metersPerSecond * 3.6
        return String(format: "%.1f%@", kmh, units ? " km/h" : "")
    }
}

func formatPace(_ mps: Double) -> String {
    guard mps > 0.2 else { return "--" }
    switch currentUnits.speed {
    case .mph:
        let minPerMile = 26.8224 / mps
        let mins = Int(minPerMile)
        let secs = Int((minPerMile - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    case .kmh:
        let minPerKm = 16.6667 / mps
        let mins = Int(minPerKm)
        let secs = Int((minPerKm - Double(mins)) * 60)
        return String(format: "%d:%02d", mins, secs)
    }
}

func formatTime(_ interval: TimeInterval) -> String {
    let hours = Int(interval) / 3600
    let minutes = (Int(interval) % 3600) / 60
    let seconds = Int(interval) % 60

    if hours > 0 {
        return String(format: "%d:%02d:%02d", hours, minutes, seconds)
    }
    return String(format: "%d:%02d", minutes, seconds)
}

func formattedStorageSize(_ bytes: Int64) -> String {
    if bytes < 1024 {
        return "\(bytes) B"
    } else if bytes < 1024 * 1024 {
        return String(format: "%.0f KB", Double(bytes) / 1024)
    } else {
        return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
    }
}

func turnColor(_ dist: Double) -> Color {
   if dist < 50 { return .red }
   if dist < 200 { return .yellow }
   return .green
}

func formatGrade(_ percent: Double) -> String {
    String(format: "%.1f", percent)
}

func formatPower(_ watts: Double) -> String {
    String(format: "%.0f", watts)
}

func formatHeartRate(_ bpm: Double) -> String {
    String(format: "%.0f", bpm)
}

func formatElevationValue(_ meters: Double) -> String {
    switch currentUnits.elevation {
    case .feet:
        let feet = meters * 3.28084
        return String(format: "%.0f", feet)
    case .meters:
        return String(format: "%.0f", meters)
    }
}

func formatHeading(_ degrees: Double) -> String {
    let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
    // Normalize degrees into [0, 360)
    let remainder = degrees.truncatingRemainder(dividingBy: 360)
    let normalizedDegrees = remainder < 0 ? remainder + 360 : remainder

    let index = Int(((normalizedDegrees + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
    let dir = dirs[max(0, min(index, dirs.count - 1))]

    // Display normalized, rounded degrees so the number matches the compass direction
    let displayDegrees = Int((normalizedDegrees.rounded()).truncatingRemainder(dividingBy: 360))

    return "\(displayDegrees)° \(dir)"
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

func buttonColor(isUploading: Bool = false, isUploadBlocked: Bool = false, isOnWatch: Bool = false) -> Color {
    if isUploading { return .orange }
    if isUploadBlocked { return .secondary }
    if isOnWatch { return .green }
    return .blue
}
