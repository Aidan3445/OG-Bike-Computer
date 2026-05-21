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

/// Formats the distance to the next turn for the watch's navigation overlay.
/// Steps the readout down through tenths of a mile/km before switching to
/// feet/meters so the rider sees "1.5 mi → 1.0 mi → 0.7 mi → 0.3 mi → 400 ft"
/// rather than jumping straight to feet. Uses digit forms (0.5 / 0.25) rather
/// than unicode glyphs (½ / ¼) which render too small on the watch.
func formatTurnDistance(_ meters: Double) -> String {
    switch currentUnits.distance {
    case .miles:
        let miles = meters / 1609.34
        if miles >= 1.0 {
            return String(format: "%.1f mi", miles)
        }
        if miles >= 0.1 {
            let tenths = (miles * 10).rounded() / 10
            return String(format: "%.1f mi", tenths)
        }
        let feet = Int(meters * 3.28084)
        return "\((feet / 50) * 50) ft"
    case .kilometers:
        let km = meters / 1000
        if km >= 1.0 {
            return String(format: "%.1f km", km)
        }
        if km >= 0.1 {
            let tenths = (km * 10).rounded() / 10
            return String(format: "%.1f km", tenths)
        }
        let m = Int(meters)
        return "\((m / 50) * 50) m"
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

func formatVoiceDistance(_ meters: Double) -> String {
    switch currentUnits.distance {
    case .miles:
        let feet = meters * 3.28084
        let miles = meters / 1609.344

        if feet < 150 {
            let rounded = max(50, Int((feet / 50).rounded()) * 50)
            return "\(rounded) feet"
        }
        if feet < 300 {
            let hundreds = Int((feet / 100).rounded())
            return "\(hundreds) hundred feet"
        }
        if miles < 0.2 {
            let rounded = Int((feet / 100).rounded()) * 100
            return "\(rounded) feet"
        }
        if miles < 0.3 { return "a quarter mile" }
        if miles < 0.6 { return "half a mile" }
        if miles < 0.85 { return "three quarters of a mile" }
        if miles < 1.1 { return "1 mile" }
        if miles < 1.3 { return "about a mile" }
        if miles < 1.7 { return "a mile and a half" }
        if miles < 2.2 { return "2 miles" }
        let rounded = Int(miles.rounded())
        return "\(rounded) miles"

    case .kilometers:
        if meters < 100 {
            let rounded = max(25, Int((meters / 25).rounded()) * 25)
            return "\(rounded) meters"
        }
        if meters < 250 {
            let rounded = Int((meters / 50).rounded()) * 50
            return "\(rounded) meters"
        }
        let km = meters / 1000
        if km < 0.4 { return "250 meters" }
        if km < 0.6 { return "half a kilometer" }
        if km < 0.85 { return "three quarters of a kilometer" }
        if km < 1.1 { return "1 kilometer" }
        if km < 1.3 { return "about a kilometer" }
        if km < 1.7 { return "a kilometer and a half" }
        if km < 2.2 { return "2 kilometers" }
        let rounded = Int(km.rounded())
        return "\(rounded) kilometers"
    }
}

/// Returns a voice-friendly direction (e.g. "turn left", "turn around") from a rider's
/// heading to a target bearing.
func voiceDirectionToTarget(heading: Double, bearingToTarget: Double) -> String {
    // Relative angle: positive = target is to the right
    var relative = bearingToTarget - heading
    // Normalize to [-180, 180]
    while relative > 180 { relative -= 360 }
    while relative < -180 { relative += 360 }

    let abs = Swift.abs(relative)
    if abs < 20 { return "continue straight" }
    if abs > 160 { return "turn around" }
    let direction = relative > 0 ? "right" : "left"
    if abs < 50 { return "bear \(direction)" }
    if abs < 130 { return "turn \(direction)" }
    return "sharp \(direction)"
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

func buttonColor(isUploading: Bool = false, isQueued: Bool = false, isUploadBlocked: Bool = false, isOnWatch: Bool = false) -> Color {
    if isUploading { return .orange }
    if isQueued { return .secondary }
    if isUploadBlocked { return .secondary }
    if isOnWatch { return .green }
    return .blue
}
