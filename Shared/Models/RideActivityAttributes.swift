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

    /// Dynamic data updated throughout the ride
    struct ContentState: Codable, Hashable {
        // Core ride stats
        var elapsedTime: TimeInterval
        var movingTime: TimeInterval
        var totalDistance: Double     // meters
        var averageSpeed: Double     // m/s
        var currentSpeed: Double     // m/s
        var heartRate: Double?

        // Navigation (nil for free rides)
        var distanceToNextTurn: Double?   // meters
        var nextTurnDirection: String?    // e.g. "Left", "Sharp Right"
        var nextTurnIcon: String?         // SF Symbol name e.g. "arrow.turn.up.left"
        var nextTurnCue: String?          // e.g. "onto Main St"
        var routeDistanceRemaining: Double? // meters

        // Off-route
        var isOffRoute: Bool
        var offRouteMessage: String?

        // Rider location for potential map rendering
        var riderLatitude: Double?
        var riderLongitude: Double?
    }
}
#endif
