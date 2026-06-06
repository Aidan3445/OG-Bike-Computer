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
    /// World-space heading of route travel at the *arrow* location, in degrees (0=N, 90=E).
    let bearingDegrees: Double
    /// Position of the travel-direction arrow — placed halfway along the route
    /// to the next marker (snapped to the nearest underlying track point) so the
    /// arrow doesn't share an annotation with the label. nil for the last
    /// marker when the route ends before the halfway point.
    let arrowCoordinate: CLLocationCoordinate2D?
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
    let halfInterval = intervalMeters / 2

    // First pass: emit the marker positions themselves, plus the along-route
    // distance where each marker's direction arrow should sit (halfway to the
    // next marker).
    struct Pending {
        let mile: Int
        let coord: CLLocationCoordinate2D
        let arrowAt: Double
    }
    var pending: [Pending] = []
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
            pending.append(Pending(
                mile: markerNumber,
                coord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                arrowAt: nextThreshold + halfInterval))

            nextThreshold += intervalMeters
        }
    }

    // Second pass: walk forward through points to snap each marker's arrow to
    // the nearest track point at its halfway-along-route distance. Skip the
    // arrow if the route ends before the halfway point.
    let totalDist = points.last?.distanceFromStart ?? 0
    var markers: [MileMarker] = []
    markers.reserveCapacity(pending.count)
    var idx = 1
    for p in pending {
        if p.arrowAt > totalDist {
            markers.append(MileMarker(
                mile: p.mile, coordinate: p.coord, bearingDegrees: 0,
                arrowCoordinate: nil))
            continue
        }
        while idx < points.count && points[idx].distanceFromStart < p.arrowAt {
            idx += 1
        }
        let bIdx = min(idx, points.count - 1)
        let aIdx = max(bIdx - 1, 0)
        let a = points[aIdx], b = points[bIdx]
        let snap = abs(a.distanceFromStart - p.arrowAt)
            <= abs(b.distanceFromStart - p.arrowAt) ? a : b
        let bearing = RouteProcessor.bearing(from: a.coordinate, to: b.coordinate)
        markers.append(MileMarker(
            mile: p.mile,
            coordinate: p.coord,
            bearingDegrees: bearing,
            arrowCoordinate: snap.coordinate))
    }

    return markers
}

/// Compute distance markers along a recorded ride track.
func computeRideMileMarkers(locations: [CLLocation], interval: Double? = nil) -> [MileMarker] {
    guard locations.count >= 2 else { return [] }

    let (metersPerUnit, defaultInterval) = distanceInterval
    let intervalUnits = interval ?? defaultInterval
    let intervalMeters = intervalUnits * metersPerUnit
    let halfInterval = intervalMeters / 2

    // Build a parallel array of cumulative distance so we can do the same
    // halfway-snap as the route version without recomputing segments.
    var cumDist: [Double] = Array(repeating: 0, count: locations.count)
    for i in 1..<locations.count {
        cumDist[i] = cumDist[i - 1] + locations[i].distance(from: locations[i - 1])
    }

    struct Pending {
        let mile: Int
        let coord: CLLocationCoordinate2D
        let arrowAt: Double
    }
    var pending: [Pending] = []
    var nextThreshold = intervalMeters

    for i in 1..<locations.count {
        let dist = cumDist[i]
        let prevDist = cumDist[i - 1]

        while dist >= nextThreshold && prevDist < nextThreshold {
            let segDist = dist - prevDist
            let ratio = segDist > 0 ? (nextThreshold - prevDist) / segDist : 0

            let lat = locations[i - 1].coordinate.latitude +
                (locations[i].coordinate.latitude - locations[i - 1].coordinate.latitude) * ratio
            let lon = locations[i - 1].coordinate.longitude +
                (locations[i].coordinate.longitude - locations[i - 1].coordinate.longitude) * ratio

            let markerNumber = Int(round(nextThreshold / metersPerUnit))
            pending.append(Pending(
                mile: markerNumber,
                coord: CLLocationCoordinate2D(latitude: lat, longitude: lon),
                arrowAt: nextThreshold + halfInterval))

            nextThreshold += intervalMeters
        }
    }

    let totalDist = cumDist.last ?? 0
    var markers: [MileMarker] = []
    markers.reserveCapacity(pending.count)
    var idx = 1
    for p in pending {
        if p.arrowAt > totalDist {
            markers.append(MileMarker(
                mile: p.mile, coordinate: p.coord, bearingDegrees: 0,
                arrowCoordinate: nil))
            continue
        }
        while idx < locations.count && cumDist[idx] < p.arrowAt {
            idx += 1
        }
        let bIdx = min(idx, locations.count - 1)
        let aIdx = max(bIdx - 1, 0)
        let a = locations[aIdx].coordinate, b = locations[bIdx].coordinate
        let snap = abs(cumDist[aIdx] - p.arrowAt)
            <= abs(cumDist[bIdx] - p.arrowAt) ? a : b
        let bearing = RouteProcessor.bearing(from: a, to: b)
        markers.append(MileMarker(
            mile: p.mile,
            coordinate: p.coord,
            bearingDegrees: bearing,
            arrowCoordinate: snap))
    }

    return markers
}
