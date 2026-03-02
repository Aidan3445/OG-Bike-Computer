//
//  RouteProcessor.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

struct RouteProcessor {
    static let turnAngleThreshold: Double = 30

    static let minTurnSpacing: Double = 50

    static func process(_ route: Route) -> ProcessedRoute {
        let coords = route.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        guard coords.count >= 2 else {
            return ProcessedRoute(
                name: route.name,
                points: [],
                turnPoints: [],
                totalDistance: 0,
                minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
        }

        // Step 1: Compute distances, cumulative distance, and bearings
        var cumulativeDistance: Double = 0
        var processedPoints: [ProcessedPoint] = []

        for i in 0..<coords.count {
            if i > 0 {
                let prev = CLLocation(latitude: coords[i-1].latitude, longitude: coords[i-1].longitude)
                let curr = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                cumulativeDistance += curr.distance(from: prev)
            }

            let bearing: Double
            if i < coords.count - 1 {
                bearing = self.bearing(from: coords[i], to: coords[i+1])
            } else {
                bearing = processedPoints.last?.bearingToNext ?? 0
            }

            processedPoints.append(ProcessedPoint(
                coordinate: coords[i],
                elevation: route.points[i].elevation,
                distanceFromStart: cumulativeDistance,
                bearingToNext: bearing))
        }

        // Step 2: Detect turns
        var turnPoints: [TurnPoint] = []
        var lastTurnDistance: Double = -minTurnSpacing

        for i in 1..<(processedPoints.count - 1) {
            let prevBearing = processedPoints[i-1].bearingToNext
            let nextBearing = processedPoints[i].bearingToNext
            let angle = angleDelta(from: prevBearing, to: nextBearing)

            if abs(angle) >= turnAngleThreshold {
                let dist = processedPoints[i].distanceFromStart
                if dist - lastTurnDistance >= minTurnSpacing {
                    let direction = classifyTurn(angle)
                    turnPoints.append(TurnPoint(
                        index: i,
                        angle: angle,
                        direction: direction,
                        distanceFromStart: dist,
                        coordinate: coords[i]))
                    lastTurnDistance = dist
                }
            }
        }

        // Step 3: Bounding box
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }

        return ProcessedRoute(
            name: route.name,
            points: processedPoints,
            turnPoints: turnPoints,
            totalDistance: cumulativeDistance,
            minLat: lats.min()!, maxLat: lats.max()!,
            minLon: lons.min()!, maxLon: lons.max()!)
    }

    nonisolated static func bearing(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let dLon = radians(b.longitude - a.longitude)
        let aLat = radians(a.latitude)
        let bLat = radians(b.latitude)

        let y = sin(dLon) * cos(bLat)
        let x = cos(aLat) * sin(bLat) - sin(aLat) * cos(bLat) * cos(dLon)

        let bearing = atan2(y, x)
        return (degrees(bearing) + 360).truncatingRemainder(dividingBy: 360)
    }

    nonisolated static func angleDelta(from a: Double, to b: Double) -> Double {
        var delta = b - a
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    nonisolated static func classifyTurn(_ angle: Double) -> TurnDirection {
        let a = angle
        if a < -150 || a > 150 { return .uTurn }
        if a < -100 { return .sharpLeft }
        if a < -45 { return .left }
        if a < -15 { return .slightLeft }
        if a > 100 { return .sharpRight }
        if a > 45 { return .right }
        if a > 15 { return .slightRight }
        return .straight
    }

    nonisolated private static func radians(_ degrees: Double) -> Double { degrees * .pi / 180 }
    nonisolated private static func degrees(_ radians: Double) -> Double { radians * 180 / .pi }
}
