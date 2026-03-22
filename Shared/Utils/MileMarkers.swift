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

/// Compute mile marker positions along a route at every `intervalMiles` miles.
func computeMileMarkers(points: [ProcessedPoint], intervalMiles: Double = 5) -> [MileMarker] {
    guard points.count >= 2 else { return [] }

    let intervalMeters = intervalMiles * 1609.34
    var markers: [MileMarker] = []
    var nextThreshold = intervalMeters

    for i in 1..<points.count {
        let dist = points[i].distanceFromStart
        let prevDist = points[i - 1].distanceFromStart

        while dist >= nextThreshold && prevDist < nextThreshold {
            // Interpolate position at the threshold
            let segLen = dist - prevDist
            let ratio = segLen > 0 ? (nextThreshold - prevDist) / segLen : 0

            let lat = points[i - 1].coordinate.latitude +
                (points[i].coordinate.latitude - points[i - 1].coordinate.latitude) * ratio
            let lon = points[i - 1].coordinate.longitude +
                (points[i].coordinate.longitude - points[i - 1].coordinate.longitude) * ratio

            let mileNumber = Int(round(nextThreshold / 1609.34))
            markers.append(MileMarker(
                mile: mileNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))

            nextThreshold += intervalMeters
        }
    }

    return markers
}

/// Compute mile markers along a recorded ride track.
func computeRideMileMarkers(locations: [CLLocation], intervalMiles: Double = 5) -> [MileMarker] {
    guard locations.count >= 2 else { return [] }

    let intervalMeters = intervalMiles * 1609.34
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

            let mileNumber = Int(round(nextThreshold / 1609.34))
            markers.append(MileMarker(
                mile: mileNumber,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)))

            nextThreshold += intervalMeters
        }
    }

    return markers
}
