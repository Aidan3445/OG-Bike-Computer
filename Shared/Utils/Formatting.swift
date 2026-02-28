//
//  Formatting.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation

func formatDistance(_ meters: Double) -> String {
    let miles = meters / 1609.34
    return String(format: "%.1f mi", miles)
}

func formatElevation(_ meters: Double) -> String {
   let feet = meters * 3.28084
   return String(format: "%.0f ft", feet)
}

func formatSpeed(_ metersPerSecond: Double) -> String {
    let mph = metersPerSecond * 2.23694
    return String(format: "%.1f", mph)
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
