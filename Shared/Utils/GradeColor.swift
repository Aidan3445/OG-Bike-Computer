//
//  GradeColor.swift
//  OG Bike Computer
//

import SwiftUI

/// Grade tiers shared by the watch elevation screen and the phone charts.
func gradeColor(_ pct: Double) -> Color {
    switch pct {
    case ..<(-3):     return .blue
    case ..<3:        return .green
    case ..<6:        return .yellow
    case ..<10:       return .orange
    default:          return .red
    }
}

/// "6.2%", with tiny negatives shown as "0.0%" instead of "-0.0%".
func gradeLabel(_ pct: Double) -> String {
    let rounded = (pct * 10).rounded() / 10
    return formatGrade(rounded == 0 ? 0 : rounded) + "%"
}
