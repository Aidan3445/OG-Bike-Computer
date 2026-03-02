//
//  Formatting.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import SwiftUI

func formatDistance(_ meters: Double, _ units: Bool = true) -> String {
    let miles = meters / 1609.34
    return String(format: "%.1f%@", miles, units ? " mi" : "")
}

func formatTurnDistance(_ meters: Double) -> String {
    if meters >= 1609 {
        return String(format: "%.1f", meters / 1609.34)
    } else {
        let feet = Int(meters * 3.28084)
        return "\((feet / 50) * 50) ft"
    }
}

func formatElevation(_ meters: Double) -> String {
   let feet = meters * 3.28084
   return String(format: "%.0f ft", feet)
}

func formatSpeed(_ metersPerSecond: Double) -> String {
    let mph = metersPerSecond * 2.23694
    return String(format: "%.1f", mph)
}

func formatPace(_ mps: Double) -> String {
    guard mps > 0.2 else { return "--" }
    let minPerMile = 26.8224 / mps
    let mins = Int(minPerMile)
    let secs = Int((minPerMile - Double(mins)) * 60)
    return String(format: "%d:%02d", mins, secs)
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

func buttonColor(isUploading: Bool = false, isUploadBlocked: Bool = false, isOnWatch: Bool = false) -> Color {
    if isUploading { return .orange }
    if isUploadBlocked { return .secondary }
    if isOnWatch { return .green }
    return .blue
}
