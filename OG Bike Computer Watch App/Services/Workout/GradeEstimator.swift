//
//  GradeEstimator.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Smoothed road grade in percent. On a route it comes from the route's
/// elevation around the rider, otherwise from GPS altitude over a short
/// stretch of road.
struct GradeEstimator {
    /// Steeper than any paved road, so anything past it is noise.
    static let maxGrade: Double = 45

    private var window: [CLLocation] = []

    /// The next grade, smoothed from `current`. Stays at `current` when the
    /// GPS window can't give one.
    mutating func update(
        location: CLLocation, routeGrade: Double?, current: Double, smoothing: ElevationSmoothing
    ) -> Double {
        if let routeGrade {
            let alpha = smoothing.routeGradeAlpha
            return current * (1 - alpha) + routeGrade * alpha
        }

        window.append(location)
        while window.count > 2,
            Self.horizontalDistance(from: window[0], to: location) > smoothing.gradeWindowDistance * 2
        {
            window.removeFirst()
        }

        let first = window[0]
        guard window.count >= 2, Self.hasUsableAltitude(first), Self.hasUsableAltitude(location)
        else { return current }
        let run = Self.horizontalDistance(from: first, to: location)
        guard run > 10 else { return current }
        let rawGrade = (location.altitude - first.altitude) / run * 100
        let alpha = smoothing.gpsGradeAlpha
        return current * (1 - alpha) + Self.clamp(rawGrade) * alpha
    }

    mutating func reset() {
        window = []
    }

    /// Grade from the route's elevation 25 m either side of the rider. Nil
    /// off route or where the route has no elevation.
    static func routeGrade(from navigation: NavigationTracker) -> Double? {
        guard let route = navigation.processedRoute, !navigation.isOffRoute else { return nil }

        let points = route.points
        let segIdx = navigation.currentSegmentIndex
        guard segIdx < points.count else { return nil }

        let currentDist = navigation.distanceAlongRoute
        let reach: Double = 25

        var behindIdx = segIdx
        while behindIdx > 0 && (currentDist - points[behindIdx].distanceFromStart) < reach {
            behindIdx -= 1
        }
        var aheadIdx = segIdx
        while aheadIdx < points.count - 1
            && (points[aheadIdx].distanceFromStart - currentDist) < reach
        {
            aheadIdx += 1
        }

        guard let elevBehind = points[behindIdx].elevation,
            let elevAhead = points[aheadIdx].elevation
        else { return nil }

        let run = points[aheadIdx].distanceFromStart - points[behindIdx].distanceFromStart
        guard run > 10 else { return nil }
        return clamp((elevAhead - elevBehind) / run * 100)
    }

    private static func clamp(_ grade: Double) -> Double {
        max(-maxGrade, min(maxGrade, grade))
    }

    private static func hasUsableAltitude(_ location: CLLocation) -> Bool {
        location.verticalAccuracy >= 0 && location.verticalAccuracy < 20
    }

    private static func horizontalDistance(from a: CLLocation, to b: CLLocation) -> Double {
        let flatA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
        let flatB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
        return flatA.distance(from: flatB)
    }
}
