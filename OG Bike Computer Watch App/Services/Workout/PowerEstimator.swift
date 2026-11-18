//
//  PowerEstimator.swift
//  OG Bike Computer Watch App
//

import Foundation

/// Rider power from speed, grade and mass, with no power meter:
/// P = (gravity + rolling resistance + drag) * v.
enum PowerEstimator {
    /// Below this speed (m/s) the rider counts as stopped and power is 0.
    static let minSpeed = 0.5

    private static let gravity = 9.81
    private static let rollingResistance = 0.005
    /// Drag area (m²) for an upright rider.
    private static let dragArea = 0.4
    /// Air density (kg/m³) at sea level.
    private static let airDensity = 1.225

    static func watts(speed: Double, gradePercent: Double, mass: Double) -> Double {
        let slope = atan(gradePercent / 100)
        let climbing = mass * gravity * sin(slope)
        let rolling = rollingResistance * mass * gravity * cos(slope)
        let drag = 0.5 * dragArea * airDensity * speed * speed
        return max(0, (climbing + rolling + drag) * speed)
    }
}
