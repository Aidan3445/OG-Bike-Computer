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
}

/// Unit-aware interval in meters and divisor for label numbers.
private var distanceInterval: (metersPerUnit: Double, defaultInterval: Double) {
    switch currentUnits.distance {
    case .miles: return (1609.34, 5)
    case .kilometers: return (1000, 5)
    }
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
            markers.append(MileMarker(
                mile: markerNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))

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
            markers.append(MileMarker(
                mile: markerNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))

            nextThreshold += intervalMeters
        }
    }

    return markers
}
