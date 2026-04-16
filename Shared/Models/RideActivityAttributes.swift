//
//  RideActivityAttributes.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

struct RideActivityAttributes: ActivityAttributes {
    /// Static data set when the activity starts
    var routeName: String?
    var startTime: Date
    var isImperial: Bool
    /// Which 6 metrics to show in the lock-screen stats grid (MetricType raw values).
    /// Defaults to distance, moving time, avg speed, heart rate, elev gain, speed.
    var statSlots: [String] = ["distance", "movingTime", "averageSpeed", "heartRate", "elevationGain", "speed"]

    /// Dynamic data updated throughout the ride
    struct ContentState: Codable, Hashable {
        // Core ride stats
        var elapsedTime: TimeInterval
        var movingTime: TimeInterval
        var totalDistance: Double     // meters
        var averageSpeed: Double     // m/s
        var currentSpeed: Double     // m/s
        var heartRate: Double?

        // Extended stats
        var maxSpeed: Double?            // m/s
        var averageHeartRate: Double?
        var maxHeartRate: Double?
        var activeCalories: Double?
        var currentElevation: Double?    // meters
        var elevationGain: Double?       // meters
        var elevationLoss: Double?       // meters
        var highestElevation: Double?    // meters
        var currentGrade: Double?        // percent
        var estimatedPower: Double?      // watts

        // Navigation (nil for free rides)
        var distanceToNextTurn: Double?   // meters
        var nextTurnDirection: String?    // e.g. "Left", "Sharp Right"
        var nextTurnIcon: String?         // SF Symbol name e.g. "arrow.turn.up.left"
        var nextTurnCue: String?          // e.g. "onto Main St"
        var routeDistanceRemaining: Double? // meters

        // Ride state
        var isPaused: Bool
        var isAutoPaused: Bool

        // Off-route
        var isOffRoute: Bool
        var distanceOffRoute: Double?   // meters from nearest route point

        // Rider location for potential map rendering
        var riderLatitude: Double?
        var riderLongitude: Double?
    }
}
#endif
