//
//  RouteElevationSimplifier.swift
//  OG Bike Computer
//
//  Produces a simplified elevation series for fast rendering on the watch.
//  Uses Ramer-Douglas-Peucker on (distance, elevation) to keep peaks/valleys
//  while collapsing flat sections.
//

import Foundation
import CoreLocation

enum RouteElevationSimplifier {
    /// Maximum number of points kept in the simplified series. The watch's
    /// elevation chart targets this; raising it costs render time.
    static let targetMaxPoints: Int = 250

    /// Generate a simplified elevation series for a Route.
    /// Returns nil if the route has no usable elevation data.
    static func simplify(_ route: Route, maxPoints: Int = targetMaxPoints) -> [ElevationSample]? {
        // Build (distanceFromStart, elevation) samples from the raw track,
        // dropping any points without elevation.
        var raw: [ElevationSample] = []
        raw.reserveCapacity(route.points.count)

        var cumulative: Double = 0
        var previous: TrackPoint?
        for pt in route.points {
            if let prev = previous {
                let p1 = CLLocation(latitude: prev.lat, longitude: prev.lon)
                let p2 = CLLocation(latitude: pt.lat, longitude: pt.lon)
                cumulative += p2.distance(from: p1)
            }
            previous = pt
            if let elev = pt.elevation {
                raw.append(ElevationSample(distanceFromStart: cumulative, elevation: elev))
            }
        }

        guard raw.count > 2 else {
            return raw.isEmpty ? nil : raw
        }

        if raw.count <= maxPoints { return raw }

        // First pass: vertical-distance RDP. Tolerance is set so that
        // small bumps under ~3m are absorbed but real peaks survive.
        let elevations = raw.map(\.elevation)
        let span = (elevations.max() ?? 0) - (elevations.min() ?? 0)
        let baseTolerance = max(2.0, span * 0.005)  // 0.5% of total span, min 2m

        var simplified = rdp(raw, tolerance: baseTolerance)

        // If still too dense, increase tolerance until we fit.
        var tolerance = baseTolerance
        var safety = 12
        while simplified.count > maxPoints && safety > 0 {
            tolerance *= 1.6
            simplified = rdp(raw, tolerance: tolerance)
            safety -= 1
        }

        // If we *still* over-shoot (very long route), uniform-stride downsample.
        if simplified.count > maxPoints {
            let stride = Int(ceil(Double(simplified.count) / Double(maxPoints)))
            var trimmed: [ElevationSample] = []
            trimmed.reserveCapacity(maxPoints + 2)
            for i in Swift.stride(from: 0, to: simplified.count, by: stride) {
                trimmed.append(simplified[i])
            }
            if let last = simplified.last, trimmed.last?.distanceFromStart != last.distanceFromStart {
                trimmed.append(last)
            }
            simplified = trimmed
        }

        return simplified
    }

    // MARK: - RDP

    private static func rdp(_ points: [ElevationSample], tolerance: Double) -> [ElevationSample] {
        guard points.count > 2 else { return points }
        var keep = [Bool](repeating: false, count: points.count)
        keep[0] = true
        keep[points.count - 1] = true
        rdpRecurse(points, start: 0, end: points.count - 1, tolerance: tolerance, keep: &keep)
        return zip(points, keep).compactMap { $1 ? $0 : nil }
    }

    private static func rdpRecurse(_ points: [ElevationSample],
                                   start: Int, end: Int,
                                   tolerance: Double,
                                   keep: inout [Bool]) {
        guard end > start + 1 else { return }
        let a = points[start]
        let b = points[end]
        let dx = b.distanceFromStart - a.distanceFromStart
        let dy = b.elevation - a.elevation

        var maxDeviation: Double = 0
        var index = start

        if dx == 0 {
            for i in (start + 1)..<end {
                let d = abs(points[i].elevation - a.elevation)
                if d > maxDeviation { maxDeviation = d; index = i }
            }
        } else {
            // Perpendicular distance from point to segment a-b in (distance, elevation) space.
            let denom = (dx * dx + dy * dy).squareRoot()
            for i in (start + 1)..<end {
                let p = points[i]
                let num = abs(dy * p.distanceFromStart - dx * p.elevation
                              + b.distanceFromStart * a.elevation
                              - b.elevation * a.distanceFromStart)
                let dist = num / denom
                if dist > maxDeviation {
                    maxDeviation = dist
                    index = i
                }
            }
        }

        if maxDeviation > tolerance {
            keep[index] = true
            rdpRecurse(points, start: start, end: index, tolerance: tolerance, keep: &keep)
            rdpRecurse(points, start: index, end: end, tolerance: tolerance, keep: &keep)
        }
    }
}
