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
    static let minBearingDistance: Double = 5
    static let minTurnSpacing: Double = 50

    static func process(_ route: Route) -> ProcessedRoute {
        let coords = route.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        guard coords.count >= 2 else {
            return ProcessedRoute(
                name: route.name,
                points: [],
                waypointTurnPoints: [],
                calculatedTurnPoints: [],
                totalDistance: 0,
                hasWaypoints: false,
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
                // Look ahead past nearby points to get a stable bearing.
                // GPS noise between close points causes wild bearing swings.
                var target = i + 1
                let origin = CLLocation(latitude: coords[i].latitude, longitude: coords[i].longitude)
                while target < coords.count - 1 {
                    let candidate = CLLocation(latitude: coords[target].latitude, longitude: coords[target].longitude)
                    if origin.distance(from: candidate) >= minBearingDistance {
                        break
                    }
                    target += 1
                }
                bearing = self.bearing(from: coords[i], to: coords[target])
            } else {
                bearing = processedPoints.last?.bearingToNext ?? 0
            }

            processedPoints.append(ProcessedPoint(
                coordinate: coords[i],
                elevation: route.points[i].elevation,
                distanceFromStart: cumulativeDistance,
                bearingToNext: bearing))
        }

        // Step 2: Detect calculated turns
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

        // Step 2b: Remove canceling turn pairs
        // Two turns within cancelPairDistance whose angles roughly
        // cancel out (sum near zero) are noise, not real turns.
        let cancelPairDistance: Double = 100 // meters apart
        let cancelAngleThreshold: Double = 40 // net angle must be below this

        var filtered: [TurnPoint] = []
        var skip = false
        for j in 0..<turnPoints.count {
            if skip {
                skip = false
                continue
            }
            if j + 1 < turnPoints.count {
                let a = turnPoints[j]
                let b = turnPoints[j + 1]
                let gap = b.distanceFromStart - a.distanceFromStart
                let netAngle = abs(a.angle + b.angle)
                if gap <= cancelPairDistance && netAngle < cancelAngleThreshold {
                    // Pair cancels out — skip both
                    skip = true
                    continue
                }
            }
            filtered.append(turnPoints[j])
        }
        let calculatedTurns = filtered

        // Step 3: Map waypoints to route points (only turn-cue waypoints, not POIs)
        let waypointTurns: [TurnPoint]
        if let waypoints = route.waypoints?.turnCues, !waypoints.isEmpty {
            waypointTurns = mapWaypoints(waypoints, to: processedPoints)
        } else {
            waypointTurns = []
        }

        // Step 3b: Map POIs to route points
        let pois: [RoutePOI]
        if let routePOIs = route.waypoints?.pois, !routePOIs.isEmpty {
            pois = mapPOIs(routePOIs, to: processedPoints)
        } else {
            pois = []
        }

        // Step 4: Bounding box
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }

        // Reuse the precomputed simplified elevation if the route has one,
        // otherwise compute it now from the full track.
        let simplified = route.simplifiedElevation
            ?? RouteElevationSimplifier.simplify(route)
            ?? []

        return ProcessedRoute(
            name: route.name,
            points: processedPoints,
            waypointTurnPoints: waypointTurns,
            calculatedTurnPoints: calculatedTurns,
            pois: pois,
            simplifiedElevation: simplified,
            totalDistance: cumulativeDistance,
            hasWaypoints: !waypointTurns.isEmpty,
            minLat: lats.min()!, maxLat: lats.max()!,
            minLon: lons.min()!, maxLon: lons.max()!)
    }

    /// Map POI waypoints to the nearest route points and capture their off-route distance.
    private static func mapPOIs(_ pois: [Waypoint], to processedPoints: [ProcessedPoint]) -> [RoutePOI] {
        return pois.map { poi in
            let poiLoc = CLLocation(latitude: poi.lat, longitude: poi.lon)
            var bestIndex = 0
            var bestDist = Double.greatestFiniteMagnitude
            for i in 0..<processedPoints.count {
                let pt = processedPoints[i]
                let ptLoc = CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude)
                let dist = poiLoc.distance(from: ptLoc)
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = i
                }
            }
            return RoutePOI(
                coordinate: poi.coordinate,
                name: poi.name,
                description: poi.description,
                distanceFromStart: processedPoints[bestIndex].distanceFromStart,
                offRouteDistance: bestDist,
                nearestPointIndex: bestIndex
            )
        }
    }

    /// Map GPX waypoints to the nearest processed route points, creating TurnPoints.
    private static func mapWaypoints(_ waypoints: [Waypoint], to processedPoints: [ProcessedPoint]) -> [TurnPoint] {
        return waypoints.compactMap { wpt in
            let wptLoc = CLLocation(latitude: wpt.lat, longitude: wpt.lon)

            var bestIndex = 0
            var bestDist = Double.greatestFiniteMagnitude

            for i in 0..<processedPoints.count {
                let pt = processedPoints[i]
                let ptLoc = CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude)
                let dist = wptLoc.distance(from: ptLoc)
                if dist < bestDist {
                    bestDist = dist
                    bestIndex = i
                }
            }

            // Reject waypoints that are too far from the route
            guard bestDist < 200 else { return nil }

            let direction = TurnDirection.from(waypointName: wpt.name)

            return TurnPoint(
                index: bestIndex,
                angle: 0,
                direction: direction,
                distanceFromStart: processedPoints[bestIndex].distanceFromStart,
                coordinate: processedPoints[bestIndex].coordinate,
                description: wpt.description,
                isWaypoint: true
            )
        }
        .sorted { $0.distanceFromStart < $1.distanceFromStart }
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
