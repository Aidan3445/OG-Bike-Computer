//
//  TentativeResumeBuffer.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Fixes held back while auto-pause checks that the rider really set off.
/// They join the ride if the resume is confirmed and are dropped if not.
struct TentativeResumeBuffer {
    private(set) var locations: [CLLocation] = []
    /// Meters between the staged fixes, not counting the gap to the ride's last point.
    private(set) var distance: Double = 0
    private(set) var startTime: Date?
    private(set) var fastSampleCount = 0

    var elapsed: TimeInterval {
        startTime.map { Date().timeIntervalSince($0) } ?? 0
    }

    mutating func begin(with location: CLLocation?, fastSamples: Int) {
        clear()
        startTime = Date()
        fastSampleCount = fastSamples
        if let location { locations.append(location) }
    }

    mutating func append(_ location: CLLocation) {
        if let prev = locations.last {
            distance += location.distance(from: prev)
        }
        locations.append(location)
    }

    mutating func countFastSample() {
        fastSampleCount += 1
    }

    mutating func clear() {
        locations = []
        distance = 0
        startTime = nil
        fastSampleCount = 0
    }
}
