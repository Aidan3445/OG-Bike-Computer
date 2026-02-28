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
