//
//  RouteProcessor.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

nonisolated struct RouteProcessor {
    static let turnAngleThreshold: Double = 30
    static let minBearingDistance: Double = 5
    static let minTurnSpacing: Double = 50
    static let waypointMatchRadius: Double = 200
    static let waypointOrderTolerance: Double = 50
    static let waypointOutOfOrderPenalty: Double = 300
    static let waypointShapeMismatchPenalty: Double = 150

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
                cueEdits: route.cueEdits,
                minLat: 0, maxLat: 0, minLon: 0, maxLon: 0)
        }

        let clock = StageClock()

        let processedPoints = trackPoints(coords, elevations: route.points.map(\.elevation))
        clock.mark("distances")

        let calculatedTurns = detectTurns(in: processedPoints)
        clock.mark("turns")

        // Step 3: Map waypoints to route points (only turn-cue waypoints, not POIs)
        let grid = route.waypoints?.isEmpty == false ? PointGrid(processedPoints) : nil
        let waypointTurns: [TurnPoint]
        if let waypoints = route.waypoints?.turnCues, !waypoints.isEmpty {
            waypointTurns = mapWaypoints(waypoints, to: processedPoints, grid: grid)
        } else {
            waypointTurns = []
        }
        clock.mark("cues")

        // Step 3b: Map POIs to route points
        let pois: [RoutePOI]
        if let routePOIs = route.waypoints?.pois, !routePOIs.isEmpty {
            pois = mapPOIs(routePOIs, to: processedPoints, grid: grid)
        } else {
            pois = []
        }
        clock.mark("pois")

        // Step 4: Bounding box
        let lats = coords.map { $0.latitude }
        let lons = coords.map { $0.longitude }

        // Reuse the precomputed simplified elevation if the route has one,
        // otherwise compute it now from the full track.
        let simplified = route.simplifiedElevation
            ?? RouteElevationSimplifier.simplify(route)
            ?? []
        clock.mark("elevation")
        DiagnosticsLog.event("RouteLoad", "processed points=\(coords.count) cues=\(waypointTurns.count) pois=\(pois.count) | \(clock.summary)")

        return ProcessedRoute(
            name: route.name,
            points: processedPoints,
            waypointTurnPoints: waypointTurns,
            calculatedTurnPoints: calculatedTurns,
            pois: pois,
            simplifiedElevation: simplified,
            totalDistance: processedPoints.last?.distanceFromStart ?? 0,
            hasWaypoints: !waypointTurns.isEmpty,
            cueEdits: route.cueEdits,
            minLat: lats.min()!, maxLat: lats.max()!,
            minLon: lons.min()!, maxLon: lons.max()!)
    }

    /// Cumulative distance and a look-ahead bearing for each coordinate.
    static func trackPoints(_ coords: [CLLocationCoordinate2D], elevations: [Double?]? = nil) -> [ProcessedPoint] {
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
                elevation: elevations?[i],
                distanceFromStart: cumulativeDistance,
                bearingToNext: bearing))
        }
        return processedPoints
    }

    /// Turns found from bearing changes along the track.
    static func detectTurns(in points: [ProcessedPoint]) -> [TurnPoint] {
        guard points.count >= 3 else { return [] }
        var turnPoints: [TurnPoint] = []
        var lastTurnDistance: Double = -minTurnSpacing

        for i in 1..<(points.count - 1) {
            let prevBearing = points[i-1].bearingToNext
            let nextBearing = points[i].bearingToNext
            let angle = angleDelta(from: prevBearing, to: nextBearing)

            if abs(angle) >= turnAngleThreshold {
                let dist = points[i].distanceFromStart
                if dist - lastTurnDistance >= minTurnSpacing {
                    let direction = classifyTurn(angle)
                    turnPoints.append(TurnPoint(
                        index: i,
                        angle: angle,
                        direction: direction,
                        distanceFromStart: dist,
                        coordinate: points[i].coordinate))
                    lastTurnDistance = dist
                }
            }
        }

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
        return filtered
    }

    /// Map POI waypoints to the nearest route points and capture their off-route distance.
    private static func mapPOIs(_ pois: [Waypoint], to processedPoints: [ProcessedPoint], grid: PointGrid?) -> [RoutePOI] {
        return pois.map { poi in
            let poiLoc = CLLocation(latitude: poi.lat, longitude: poi.lon)
            let near = FlatDistance(around: poi.coordinate)
            let candidates = grid?.nearest(to: poi.coordinate, using: near) ?? Array(processedPoints.indices)
            let approx = candidates.map { near.meters(to: processedPoints[$0].coordinate) }
            let cutoff = near.cutoff(for: approx.min() ?? 0)
            var bestIndex = 0
            var bestDist = Double.greatestFiniteMagnitude
            for (k, i) in candidates.enumerated() where approx[k] <= cutoff {
                let dist = poiLoc.distance(from: processedPoints[i].location)
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

    /// Map GPX waypoints to route points, creating TurnPoints.
    ///
    /// Waypoints carry no distance, and an out and back passes the same corner
    /// twice, so the nearest point can land a return-leg cue on the way out.
    /// Every pass within range is a candidate (the closest point of each), and
    /// a pass scores worse when it comes before the previous cue (cues are
    /// listed in ride order) or when the route turns the other way there.
    private static func mapWaypoints(_ waypoints: [Waypoint], to processedPoints: [ProcessedPoint], grid: PointGrid?) -> [TurnPoint] {
        var turns: [TurnPoint] = []
        var previousDistance: Double = 0

        for wpt in waypoints {
            let wptLoc = CLLocation(latitude: wpt.lat, longitude: wpt.lon)
            let near = FlatDistance(around: wpt.coordinate)
            let cutoff = near.cutoff(for: waypointMatchRadius)
            let direction = TurnDirection.from(waypointName: wpt.name)

            // Exact distances only for points the cheap check can't rule out,
            // plus their neighbors for the closest-point-of-the-pass test.
            var exact: [Int: Double] = [:]
            func dist(_ i: Int) -> Double {
                if let d = exact[i] { return d }
                let d = wptLoc.distance(from: processedPoints[i].location)
                exact[i] = d
                return d
            }

            var bestIndex: Int?
            var bestScore = Double.greatestFiniteMagnitude
            let candidates = grid?.indices(near: wpt.coordinate, within: cutoff) ?? Array(processedPoints.indices)
            for i in candidates where near.meters(to: processedPoints[i].coordinate) <= cutoff {
                let d = dist(i)
                guard d < waypointMatchRadius else { continue }
                if i > 0, dist(i - 1) < d { continue }
                if i < processedPoints.count - 1, dist(i + 1) < d { continue }

                var score = d
                if processedPoints[i].distanceFromStart < previousDistance - waypointOrderTolerance {
                    score += waypointOutOfOrderPenalty
                }
                if !turnShape(at: i, in: processedPoints, fits: direction) {
                    score += waypointShapeMismatchPenalty
                }
                if score < bestScore {
                    bestScore = score
                    bestIndex = i
                }
            }

            guard let index = bestIndex else { continue }
            previousDistance = processedPoints[index].distanceFromStart

            turns.append(TurnPoint(
                index: index,
                angle: 0,
                direction: direction,
                distanceFromStart: processedPoints[index].distanceFromStart,
                coordinate: processedPoints[index].coordinate,
                description: wpt.description,
                isWaypoint: true,
                waypointID: wpt.id
            ))
        }

        return turns.sorted { $0.distanceFromStart < $1.distanceFromStart }
    }

    /// Flat-earth distance for ruling points out before the exact CLLocation
    /// distance. Within a few kilometers it's well under 1% off, and the cutoff
    /// pads for that so no point the exact distance would keep gets dropped.
    private struct FlatDistance {
        let lat: Double
        let lon: Double
        let metersPerDegreeLon: Double
        static let metersPerDegreeLat = 111_320.0

        init(around c: CLLocationCoordinate2D) {
            lat = c.latitude
            lon = c.longitude
            metersPerDegreeLon = Self.metersPerDegreeLat * cos(c.latitude * .pi / 180)
        }

        func meters(to c: CLLocationCoordinate2D) -> Double {
            let dy = (c.latitude - lat) * Self.metersPerDegreeLat
            var dLon = c.longitude - lon
            if dLon > 180 { dLon -= 360 } else if dLon < -180 { dLon += 360 }
            let dx = dLon * metersPerDegreeLon
            return (dx * dx + dy * dy).squareRoot()
        }

        func cutoff(for meters: Double) -> Double { meters * 1.05 + 10 }
    }

    /// Route points bucketed into roughly 250 m cells, so matching a cue only
    /// looks at the cells around it instead of every point on the route.
    private struct PointGrid {
        private struct Cell: Hashable { let row: Int; let col: Int }
        static let cellMeters = 250.0
        private let latStep: Double
        private let lonStep: Double
        private var cells: [Cell: [Int]] = [:]
        private let coordinates: [CLLocationCoordinate2D]

        /// Nil for a route crossing the 180th meridian, which falls back to a full scan.
        init?(_ points: [ProcessedPoint]) {
            guard let first = points.first else { return nil }
            var minLon = first.coordinate.longitude, maxLon = minLon
            var minLat = first.coordinate.latitude, maxLat = minLat
            for p in points {
                minLon = min(minLon, p.coordinate.longitude); maxLon = max(maxLon, p.coordinate.longitude)
                minLat = min(minLat, p.coordinate.latitude); maxLat = max(maxLat, p.coordinate.latitude)
            }
            guard maxLon - minLon < 180 else { return nil }
            coordinates = points.map(\.coordinate)
            latStep = Self.cellMeters / FlatDistance.metersPerDegreeLat
            let midLat = (minLat + maxLat) / 2
            lonStep = Self.cellMeters / (FlatDistance.metersPerDegreeLat * max(cos(midLat * .pi / 180), 0.01))
            for (i, p) in points.enumerated() {
                cells[cell(p.coordinate), default: []].append(i)
            }
        }

        private func cell(_ c: CLLocationCoordinate2D) -> Cell {
            Cell(row: Int((c.latitude / latStep).rounded(.down)), col: Int((c.longitude / lonStep).rounded(.down)))
        }

        /// Every point within `meters` (flat distance) of `c`, in route order.
        func indices(near c: CLLocationCoordinate2D, within meters: Double) -> [Int] {
            let center = cell(c)
            let rows = Int((meters / (latStep * FlatDistance.metersPerDegreeLat)).rounded(.up)) + 1
            let lonMeters = lonStep * FlatDistance.metersPerDegreeLat * max(cos(c.latitude * .pi / 180), 0.01)
            let cols = Int((meters / lonMeters).rounded(.up)) + 1
            var found: [Int] = []
            for r in (center.row - rows)...(center.row + rows) {
                for col in (center.col - cols)...(center.col + cols) {
                    if let bucket = cells[Cell(row: r, col: col)] { found += bucket }
                }
            }
            return found.sorted()
        }

        /// Points that could be nearest to `c`: widens the search until the
        /// closest point found is well inside it. Nil when nothing is within
        /// about 16 km, so the caller scans everything.
        func nearest(to c: CLLocationCoordinate2D, using near: FlatDistance) -> [Int]? {
            var radius = Self.cellMeters
            while radius <= 16_000 {
                let found = indices(near: c, within: radius)
                if let closest = found.lazy.map({ near.meters(to: coordinates[$0]) }).min(),
                   near.cutoff(for: closest) <= radius {
                    return found
                }
                radius *= 2
            }
            return nil
        }
    }

    /// Whether the route bends the way `direction` says at point `i`. Checked
    /// over a tight and a wider window, since a cue can sit right on a sparse
    /// track's corner or a few meters off a dense one. Straight and unknown
    /// cues always fit.
    private static func turnShape(at i: Int, in points: [ProcessedPoint], fits direction: TurnDirection) -> Bool {
        let wantsLeft: Bool
        switch direction {
        case .left, .slightLeft, .sharpLeft: wantsLeft = true
        case .right, .slightRight, .sharpRight: wantsLeft = false
        case .straight, .uTurn: return true
        }

        var measured = false
        for window in [5.0, 25.0] {
            var before = i
            while before > 0, points[i].distanceFromStart - points[before].distanceFromStart < window { before -= 1 }
            var after = i
            while after < points.count - 1, points[after].distanceFromStart - points[i].distanceFromStart < window { after += 1 }
            guard before < i, after > i else { continue }

            let angle = angleDelta(
                from: bearing(from: points[before].coordinate, to: points[i].coordinate),
                to: bearing(from: points[i].coordinate, to: points[after].coordinate))
            measured = true
            if wantsLeft ? angle < -10 : angle > 10 { return true }
        }
        // No shape to judge at the very ends of the route.
        return !measured
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

/// Milliseconds per stage, for the RouteLoad trace.
private nonisolated final class StageClock {
    private var last = Date()
    private var parts: [String] = []
    private let start = Date()

    func mark(_ stage: String) {
        let now = Date()
        parts.append("\(stage)=\(Int(now.timeIntervalSince(last) * 1000))ms")
        last = now
    }

    var summary: String {
        (parts + ["total=\(Int(Date().timeIntervalSince(start) * 1000))ms"]).joined(separator: " ")
    }
}

nonisolated private extension ProcessedPoint {
    var location: CLLocation { CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude) }
}
