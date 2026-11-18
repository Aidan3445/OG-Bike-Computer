//
//  StopTracker.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Detect Stops' memory of a stop. Once stopped, the rider stays stopped
/// until `RideOffCheck` confirms a ride-off, so GPS wander and the step
/// counter's lag can't leak distance. Ride-off fixes are held, then join the
/// ride with their time once confirmed, or are dropped if the stop carries on.
///
/// Walking never ends a stop. Once the rider rides off, the bike has moved
/// from where they stopped to where they set off, and only pushing it there
/// counts (`pushes`). A walk to a store or a toilet and back doesn't.
struct StopTracker {
    /// GPS speed (m/s) under which a fix reads as stopped. It's low on
    /// purpose: RideOffCheck's heading and distance checks are what tell
    /// riding from wander, so there's no riding speed to reach.
    static let floor = 0.3
    /// Meters of GPS slack for being back where the rider stopped or set off.
    static let nearby: Double = 20
    /// A straight push shorter than this (m) doesn't count.
    static let pushDistance: Double = 5
    /// Fixes kept from one stop, about half an hour.
    static let maxTrace = 1800

    private(set) var isStopped = false
    /// The rider walked during this stop.
    private(set) var walked = false
    private(set) var held: [CLLocation] = []
    private var stoppedAt: CLLocation?
    /// Every usable fix since the stop, for working out the pushes.
    private var trace: [CLLocation] = []

    /// A stopped reading. Returns how many held fixes it dropped.
    mutating func stop(at location: CLLocation, walking: Bool) -> Int {
        let dropped = held.count
        if !isStopped {
            walked = false
            stoppedAt = location
            trace = []
        }
        isStopped = true
        walked = walked || walking
        held = []
        note(location)
        return dropped
    }

    /// Holds a fix while stopped. A run starts on a moving fix ridden, not
    /// walked, and only keeps the last `RideOffCheck.window` seconds. True
    /// once confirmed. `recent` is the last few seconds of fixes, this one included.
    mutating func hold(_ location: CLLocation, walking: Bool, recent: [CLLocation]) -> Bool {
        walked = walked || walking
        note(location)
        if walking {
            held = []
            return false
        }
        if ridesOffWithoutSpeed(location, recent: recent) { return true }
        guard !held.isEmpty || RideOffCheck.isMoving(location, floor: Self.floor) else { return false }
        held.append(location)
        held.removeAll { location.timestamp.timeIntervalSince($0.timestamp) > RideOffCheck.window }
        return RideOffCheck.confirms(held, floor: Self.floor)
    }

    /// Where the rider pushed the bike before riding off from `setOff`, as
    /// straight legs. Only the stretch from the last time they left the stop
    /// to the first time they reached the set-off spot counts, so walks
    /// away from a parked bike and back drop out. Rests and turns between
    /// legs are fine, so switchbacks up a climb count leg by leg.
    func pushes(before setOff: CLLocation) -> [[CLLocation]] {
        guard walked, let stoppedAt else { return [] }
        let fixes = trace.filter { $0.timestamp < setOff.timestamp }
        guard let arrived = fixes.firstIndex(where: { $0.distance(from: setOff) <= Self.nearby })
        else { return [] }
        let left = fixes[..<arrived].lastIndex { $0.distance(from: stoppedAt) <= Self.nearby } ?? 0

        var legs: [[CLLocation]] = []
        var leg: [CLLocation] = []
        func close() {
            if let first = leg.first, let last = leg.last, last.distance(from: first) >= Self.pushDistance {
                legs.append(leg)
            }
            leg = []
        }
        for fix in fixes[left...arrived] {
            guard RideOffCheck.isMoving(fix, floor: Self.floor) else {
                close()
                continue
            }
            if let first = leg.first, let last = leg.last {
                let gap = fix.timestamp.timeIntervalSince(last.timestamp)
                let turned =
                    last.distance(from: first) >= Self.pushDistance
                    && RideOffCheck.headingDelta(
                        RideOffCheck.bearing(from: first, to: last),
                        RideOffCheck.bearing(from: last, to: fix)) > RideOffCheck.headingSpread
                if gap > RideOffCheck.maxFixGap || turned {
                    let corner = turned && gap <= RideOffCheck.maxFixGap ? last : nil
                    close()
                    if let corner { leg = [corner] }
                }
            }
            leg.append(fix)
        }
        close()
        return legs
    }

    /// Ends the stop and hands back the held fixes.
    mutating func finish() -> [CLLocation] {
        let fixes = held
        reset()
        return fixes
    }

    mutating func reset() {
        isStopped = false
        walked = false
        held = []
        stoppedAt = nil
        trace = []
    }

    private mutating func note(_ location: CLLocation) {
        guard location.horizontalAccuracy <= DistanceTracker.poorFixAccuracy else { return }
        trace.append(location)
        if trace.count > Self.maxTrace { trace.removeFirst(trace.count - Self.maxTrace) }
    }

    /// With no GPS speed to go on, a ride-off is the last few fixes covering
    /// ground well away from the stop, like the ride start's fallback.
    private func ridesOffWithoutSpeed(_ location: CLLocation, recent: [CLLocation]) -> Bool {
        let last = recent.suffix(RideOffCheck.fixes)
        guard let stoppedAt, let first = last.first, last.count == RideOffCheck.fixes,
            last.allSatisfy({
                $0.speedAccuracy < 0 && $0.horizontalAccuracy <= DistanceTracker.poorFixAccuracy
            })
        else { return false }
        return location.distance(from: stoppedAt) >= DepartureDetector.fallbackDistance
            && location.distance(from: first) >= RideOffCheck.distance
    }
}
