//
//  MileMarkers.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation
import CoreLocation

struct MileMarker {
    let mile: Int
    let coordinate: CLLocationCoordinate2D
    /// World-space heading of route travel at this marker, in degrees (0=N, 90=E).
    let bearingDegrees: Double
}

/// Unit-aware interval in meters and divisor for label numbers.
private var distanceInterval: (metersPerUnit: Double, defaultInterval: Double) {
    switch currentUnits.distance {
    case .miles: return (1609.34, 5)
    case .kilometers: return (1000, 5)
    }
}

/// Pick a marker interval (min 1 unit) sized to the current map zoom.
/// Targets ~8 marker spans across the visible region so density stays readable
/// as the user zooms in/out.
func mapZoomMarkerInterval(visibleMeters: Double) -> Double {
    let (metersPerUnit, _) = distanceInterval
    let visibleUnits = visibleMeters / metersPerUnit
    guard visibleUnits > 0 else { return 1 }
    let target = max(visibleUnits / 8, 1)
    let candidates: [Double] = [
        1, 2, 5, 10, 15, 20, 25, 30, 40, 50, 75,
        100, 125, 150, 200, 250, 500, 1000, 2000, 5000]
    return candidates.min(by: { abs($0 - target) < abs($1 - target) }) ?? 1
}

/// Pick a "nice" marker interval (multiple of 5 units) that yields ~10 markers
/// along a route of `totalMeters`. Used for zoomed-out full-route views where
/// the default 5-unit spacing gets too crowded on long routes.
func autoMileMarkerInterval(totalMeters: Double) -> Double {
    let (metersPerUnit, defaultInterval) = distanceInterval
    let totalUnits = totalMeters / metersPerUnit
    guard totalUnits > 0 else { return defaultInterval }

    let candidates: [Double] = [
        5, 10, 15, 20, 25, 30, 40, 50, 75,
        100, 125, 150, 200, 250, 500, 1000, 2000, 5000]
    let target = 10.0
    return candidates.min(by: {
        abs(totalUnits / $0 - target) < abs(totalUnits / $1 - target)
    }) ?? defaultInterval
}

/// Compute distance marker positions along a route.
func computeMileMarkers(points: [ProcessedPoint], interval: Double? = nil) -> [MileMarker] {
    guard points.count >= 2 else { return [] }

    let (metersPerUnit, defaultInterval) = distanceInterval
    let intervalUnits = interval ?? defaultInterval
    let intervalMeters = intervalUnits * metersPerUnit
    var markers: [MileMarker] = []
    var nextThreshold = intervalMeters

    for i in 1..<points.count {
        let dist = points[i].distanceFromStart
        let prevDist = points[i - 1].distanceFromStart

        while dist >= nextThreshold && prevDist < nextThreshold {
            let segLen = dist - prevDist
            let ratio = segLen > 0 ? (nextThreshold - prevDist) / segLen : 0

            let lat = points[i - 1].coordinate.latitude +
                (points[i].coordinate.latitude - points[i - 1].coordinate.latitude) * ratio
            let lon = points[i - 1].coordinate.longitude +
                (points[i].coordinate.longitude - points[i - 1].coordinate.longitude) * ratio

            let markerNumber = Int(round(nextThreshold / metersPerUnit))
            let bearing = RouteProcessor.bearing(
                from: points[i - 1].coordinate, to: points[i].coordinate)
            markers.append(MileMarker(
                mile: markerNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                bearingDegrees: bearing))

            nextThreshold += intervalMeters
        }
    }

    return markers
}

/// Compute distance markers along a recorded ride track.
func computeRideMileMarkers(locations: [CLLocation], interval: Double? = nil) -> [MileMarker] {
    guard locations.count >= 2 else { return [] }

    let (metersPerUnit, defaultInterval) = distanceInterval
    let intervalUnits = interval ?? defaultInterval
    let intervalMeters = intervalUnits * metersPerUnit
    var markers: [MileMarker] = []
    var cumulativeDistance: Double = 0
    var nextThreshold = intervalMeters

    for i in 1..<locations.count {
        let segDist = locations[i].distance(from: locations[i - 1])
        let prevCumulative = cumulativeDistance
        cumulativeDistance += segDist

        while cumulativeDistance >= nextThreshold && prevCumulative < nextThreshold {
            let ratio = segDist > 0 ? (nextThreshold - prevCumulative) / segDist : 0

            let lat = locations[i - 1].coordinate.latitude +
                (locations[i].coordinate.latitude - locations[i - 1].coordinate.latitude) * ratio
            let lon = locations[i - 1].coordinate.longitude +
                (locations[i].coordinate.longitude - locations[i - 1].coordinate.longitude) * ratio

            let markerNumber = Int(round(nextThreshold / metersPerUnit))
            let bearing = RouteProcessor.bearing(
                from: locations[i - 1].coordinate, to: locations[i].coordinate)
            markers.append(MileMarker(
                mile: markerNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                bearingDegrees: bearing))

            nextThreshold += intervalMeters
        }
    }

    return markers
}
