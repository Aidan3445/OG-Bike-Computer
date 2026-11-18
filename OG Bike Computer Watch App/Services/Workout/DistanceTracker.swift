//
//  DistanceTracker.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Adds up ridden distance fix to fix, skipping gaps the rider didn't ride
/// (pauses, holds) and vague indoor fixes that only wander.
struct DistanceTracker {
    /// Fixes vaguer than this (m) need GPS speed or real travel to count.
    static let poorFixAccuracy: Double = 20

    private(set) var lastCommitted: CLLocation?
    private(set) var skipsNextGap = false
    private(set) var isHoldingPoorFix = false

    mutating func reset(anchor: CLLocation?, skipNextGap: Bool) {
        lastCommitted = anchor
        skipsNextGap = skipNextGap
        isHoldingPoorFix = false
    }

    /// The next fix starts a new leg instead of adding the distance from the last one.
    mutating func skipNextGap() {
        skipsNextGap = true
    }

    /// Starts the new leg at this fix if a gap skip is pending. True when it did.
    mutating func consumeGapSkip(at location: CLLocation) -> Bool {
        guard skipsNextGap else { return false }
        skipsNextGap = false
        isHoldingPoorFix = false
        lastCommitted = location
        return true
    }

    /// Indoors the watch gets sparse fixes tens of meters out that hop around
    /// with no GPS speed. One that hasn't left its own accuracy radius is noise.
    mutating func updatePoorFixHold(_ location: CLLocation, isSimulating: Bool) {
        guard let prev = lastCommitted else { return }
        isHoldingPoorFix = !isSimulating && Self.isPoorStationaryFix(location, from: prev)
    }

    /// Adds the fix to the ride and returns the meters it covered.
    mutating func commit(_ location: CLLocation) -> Double {
        defer { lastCommitted = location }
        return lastCommitted.map { location.distance(from: $0) } ?? 0
    }

    mutating func anchor(at location: CLLocation) {
        lastCommitted = location
    }

    private static func isPoorStationaryFix(_ location: CLLocation, from prev: CLLocation) -> Bool {
        guard location.horizontalAccuracy > poorFixAccuracy else { return false }
        let hasSpeed =
            location.speedAccuracy >= 0 && location.speed >= StopDetector.standingStillSpeed
        guard !hasSpeed else { return false }
        let radius = max(location.horizontalAccuracy, prev.horizontalAccuracy)
        return location.distance(from: prev) < radius
    }
}
