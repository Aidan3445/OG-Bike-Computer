//
//  MileMarkers.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation
import CoreLocation

nonisolated struct MileMarker {
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

/// Meters per unit and the default marker interval in that unit.
private nonisolated func markerSpacing(for unit: DistanceUnit) -> (metersPerUnit: Double, defaultInterval: Double) {
    switch unit {
    case .miles: return (1609.34, 5)
    case .kilometers: return (1000, 5)
    }
}

private var distanceInterval: (metersPerUnit: Double, defaultInterval: Double) {
    markerSpacing(for: currentUnits.distance)
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
    computeMileMarkers(points: points, interval: interval, unit: currentUnits.distance)
}

/// For callers off the main actor, which read the unit before they leave it.
nonisolated func computeMileMarkers(points: [ProcessedPoint], interval: Double?, unit: DistanceUnit)
    -> [MileMarker]
{
    guard points.count >= 2 else { return [] }

    let (metersPerUnit, defaultInterval) = markerSpacing(for: unit)
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
nonisolated func computeRideMileMarkers(
    locations: [CLLocation], interval: Double? = nil, unit: DistanceUnit
) -> [MileMarker] {
    guard locations.count >= 2 else { return [] }

    let (metersPerUnit, defaultInterval) = markerSpacing(for: unit)
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

nonisolated struct DirectionArrow {
    let coordinate: CLLocationCoordinate2D
    /// World-space heading of travel at the arrow, in degrees (0=N, 90=E).
    let bearingDegrees: Double
}

/// A track to place arrows on: points with their along-track distances, the
/// distances where one arrow stretch ends and the next begins (turns, pause
/// gaps), and stretches that get no arrow at all.
nonisolated struct ArrowTrack {
    let coordinates: [CLLocationCoordinate2D]
    let distances: [Double]
    let breaks: [Double]
    var skips: [ClosedRange<Double>] = []
}

/// Above this span the mile marker arrows are enough. Below it, arrows go
/// between turns instead, since markers can't get closer than 1 mile or km.
private let segmentArrowMaxSpanMeters: Double = 6_000

/// Longest gap between segment arrows for the visible span, about a quarter
/// of the screen. nil when zoomed out far enough to use marker arrows. Snaps
/// to fixed steps so small zoom changes don't recompute the arrows.
func segmentArrowSpacing(visibleMeters: Double) -> Double? {
    guard visibleMeters > 0, visibleMeters <= segmentArrowMaxSpanMeters else { return nil }
    let target = visibleMeters / 4
    let candidates: [Double] = [50, 100, 200, 300, 500, 750, 1000, 1500]
    return candidates.min(by: { abs($0 - target) < abs($1 - target) })
}

/// One arrow in the middle of every stretch between breaks, plus evenly
/// spaced extras when a stretch is longer than `spacing`. Stretches shorter
/// than a quarter of `spacing` would crowd the turns on screen, so they get
/// none.
nonisolated func computeSegmentArrows(on track: ArrowTrack, spacing: Double) -> [DirectionArrow] {
    let coords = track.coordinates, dists = track.distances
    guard coords.count >= 2, coords.count == dists.count, spacing > 0,
          let start = dists.first, let end = dists.last, end > start
    else { return [] }

    func position(at d: Double) -> CLLocationCoordinate2D {
        var lo = 0, hi = dists.count - 1
        if d <= dists[lo] { return coords[lo] }
        if d >= dists[hi] { return coords[hi] }
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if dists[mid] <= d { lo = mid } else { hi = mid }
        }
        let len = dists[hi] - dists[lo]
        let t = len > 0 ? (d - dists[lo]) / len : 0
        let a = coords[lo], b = coords[hi]
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    let stops = [start] + track.breaks.filter { $0 > start && $0 < end }.sorted() + [end]
    let minStretch = spacing / 4
    var arrows: [DirectionArrow] = []

    for (s, e) in zip(stops, stops.dropFirst()) {
        let length = e - s
        guard length >= minStretch,
              !track.skips.contains(where: { $0.lowerBound <= s && e <= $0.upperBound })
        else { continue }
        let count = max(1, Int((length / spacing).rounded(.up)))
        // Heading over a short window so GPS jitter at one point doesn't
        // spin the arrow, kept inside the stretch so it never reads a turn.
        let window = min(15, length / 4)
        for k in 0..<count {
            let d = s + length * (Double(k) + 0.5) / Double(count)
            let before = position(at: max(s, d - window))
            let after = position(at: min(e, d + window))
            arrows.append(DirectionArrow(
                coordinate: position(at: d),
                bearingDegrees: RouteProcessor.bearing(from: before, to: after)))
        }
    }
    return arrows
}
