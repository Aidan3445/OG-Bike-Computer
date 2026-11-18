//
//  RideOffCheck.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Tells a rider moving off from GPS wander, for both stop modes. GPS speed
/// comes from the signal's Doppler shift, so it stays near zero through the
/// position jumps a stop produces. A ride-off is a few fixes in a row moving
/// on one heading that also carry the rider somewhere.
enum RideOffCheck {
    /// Speed accuracy (m/s) a fix needs for its speed to count at any pace.
    /// This watch reads about 0.9 outdoors and 1.3 or worse indoors.
    static let speedAccuracyCap = 1.2
    /// Past the cap, a speed still counts at this many times its accuracy.
    static let vagueSpeedFactor = 1.5
    static let fixes = 3
    /// Seconds allowed between those fixes.
    static let maxFixGap: TimeInterval = 3
    /// Degrees each heading can be from their average.
    static let headingSpread = 45.0
    static let duration: TimeInterval = 2
    static let distance: Double = 8
    /// Seconds of fixes a ride-off is judged on, so a stop can't build up a
    /// long run of vague fixes that later counts as moving.
    static let window: TimeInterval = 15

    static func isMoving(_ fix: CLLocation, floor: Double) -> Bool {
        fix.speedAccuracy >= 0 && fix.course >= 0 && fix.speed >= floor
            && (fix.speedAccuracy <= speedAccuracyCap || fix.speed >= vagueSpeedFactor * fix.speedAccuracy)
    }

    static func isStopped(_ fix: CLLocation, floor: Double) -> Bool {
        fix.speedAccuracy >= 0 && fix.speed < floor
    }

    /// The last few fixes are moving on one heading.
    static func isMovingSteadily(_ fixes: [CLLocation], floor: Double) -> Bool {
        let last = Array(fixes.suffix(Self.fixes))
        guard last.count == Self.fixes, last.allSatisfy({ isMoving($0, floor: floor) }) else { return false }
        let gaps = zip(last, last.dropFirst()).map { $1.timestamp.timeIntervalSince($0.timestamp) }
        return gaps.allSatisfy { $0 <= maxFixGap } && headingsAgree(last)
    }

    /// The last few fixes are all stopped.
    static func isStoppedSteadily(_ fixes: [CLLocation], floor: Double) -> Bool {
        let last = fixes.suffix(Self.fixes)
        return last.count == Self.fixes && last.allSatisfy { isStopped($0, floor: floor) }
    }

    /// `run` is every fix since the rider started moving.
    static func confirms(_ run: [CLLocation], floor: Double) -> Bool {
        guard isMovingSteadily(run, floor: floor), let first = run.first, let last = run.last else {
            return false
        }
        return last.timestamp.timeIntervalSince(first.timestamp) >= duration
            && last.distance(from: first) >= distance
    }

    /// Degrees from `a` to `b`, clockwise from north.
    static func bearing(from a: CLLocation, to b: CLLocation) -> Double {
        let lat1 = a.coordinate.latitude * .pi / 180
        let lat2 = b.coordinate.latitude * .pi / 180
        let dLon = (b.coordinate.longitude - a.coordinate.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    static func headingDelta(_ a: Double, _ b: Double) -> Double {
        abs((a - b + 540).truncatingRemainder(dividingBy: 360) - 180)
    }

    /// Headings come from the positions, not `course`. GPS course holds its
    /// last value when the rider slows or the session pauses, so it agrees
    /// with itself while the fixes go somewhere else.
    private static func headingsAgree(_ fixes: [CLLocation]) -> Bool {
        let bearings = zip(fixes, fixes.dropFirst()).map { bearing(from: $0.0, to: $0.1) }
        let radians = bearings.map { $0 * .pi / 180 }
        let x = radians.reduce(0.0) { $0 + cos($1) }
        let y = radians.reduce(0.0) { $0 + sin($1) }
        guard x * x + y * y > 1e-6 else { return false }
        let mean = atan2(y, x) * 180 / .pi
        return bearings.allSatisfy { headingDelta($0, mean) <= headingSpread }
    }
}
