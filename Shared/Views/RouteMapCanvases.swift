//
//  RouteMapCanvases.swift
//  OG Bike Computer
//
//  Shared Canvas-based renderers for the route map. Used live on the watch
//  (driven by WorkoutManager) and on the phone Settings preview (driven by
//  mock data) so both surfaces draw identically.
//

import SwiftUI
import CoreLocation

// MARK: - Render state

/// Value-type snapshot of everything the route-map canvases need to draw.
/// Built by the watch from WorkoutManager and by the phone preview from
/// a mocked sample route.
struct RouteMapData {
    var currentLocation: CLLocation?
    var processedRoute: ProcessedRoute?
    var currentSegmentIndex: Int
    var distanceAlongRoute: Double
    var heading: Double           // degrees, 0 = north
    var speed: Double             // m/s
    var recordedLocations: [CLLocation]
    var isOffRoute: Bool
    /// Off-route rejoin candidate coordinates, ordered best-first.
    var rejoinCandidateCoords: [CLLocationCoordinate2D]
    var showWaypointsOnRouteMap: Bool

    init(
        currentLocation: CLLocation? = nil,
        processedRoute: ProcessedRoute? = nil,
        currentSegmentIndex: Int = 0,
        distanceAlongRoute: Double = 0,
        heading: Double = 0,
        speed: Double = 0,
        recordedLocations: [CLLocation] = [],
        isOffRoute: Bool = false,
        rejoinCandidateCoords: [CLLocationCoordinate2D] = [],
        showWaypointsOnRouteMap: Bool = true
    ) {
        self.currentLocation = currentLocation
        self.processedRoute = processedRoute
        self.currentSegmentIndex = currentSegmentIndex
        self.distanceAlongRoute = distanceAlongRoute
        self.heading = heading
        self.speed = speed
        self.recordedLocations = recordedLocations
        self.isOffRoute = isOffRoute
        self.rejoinCandidateCoords = rejoinCandidateCoords
        self.showWaypointsOnRouteMap = showWaypointsOnRouteMap
    }

    var hasRoute: Bool { processedRoute != nil }
}

extension Color {
    /// Completed part of a route. Dark enough that it never matches any hue
    /// in the rainbow route color.
    static let riddenRoute = Color(red: 0, green: 0.45, blue: 0.15)
}

// MARK: - Route line layout

/// How far around the rider the route is drawn thick. Past this it's drawn
/// thin and dimmer so the stretch immediately ahead stands out on winding
/// roads. Both breadcrumb renderers share these so switching between them
/// (like when the screen dims) doesn't move the boundary.
enum RouteLineLayout {
    static func nearBehind(_ viewDistance: Double) -> Double { viewDistance }
    static func nearAhead(_ viewDistance: Double) -> Double { viewDistance * 2.5 }
    static let nearLineWidth: CGFloat = 6
    static let farLineWidth: CGFloat = 3
    /// Solid colors dim the far line with opacity. The rainbow can't, since
    /// it's drawn in pieces and overlapping round caps would stack into darker
    /// dots, so it uses darker opaque colors instead.
    static let farOpacity: Double = 0.5
}

extension StrokeStyle {
    /// Rounded caps and joins for route lines. The default miter join spikes
    /// on sharp corners, and butt caps leave notches where pieces meet.
    static func roundedLine(_ width: CGFloat) -> StrokeStyle {
        StrokeStyle(lineWidth: width, lineCap: .round, lineJoin: .round)
    }
}

// MARK: - Rainbow route

/// Colors for the rainbow route. Hue is measured in cycles along the line and
/// wraps red to red, so the fade has no bands or seam. Hue is pinned to the
/// line rather than animated, so riding faster just moves you through the
/// colors faster.
enum RouteRainbow {
    /// Free-ride trails: each stretch adds hue based on how fast it was
    /// ridden. Meters per cycle is this divided by speed in m/s, which works
    /// out to 2.5 mi per rainbow at 20 mph and 5 mi at 10 mph.
    static let trailCycleConstant: Double = 35_972

    struct Vertex {
        var point: CGPoint
        var cycle: Double
    }

    /// Planned routes: one full rainbow every two default-zoom distances, so a
    /// 1/4 mi default zoom cycles every 1/2 mi. It follows the default zoom
    /// rather than the current one so zooming doesn't recolor the route.
    static func routeWavelength(defaultZoom: Double) -> Double {
        defaultZoom * 2
    }

    static func routeCycle(at distance: Double, defaultZoom: Double) -> Double {
        distance / routeWavelength(defaultZoom: defaultZoom)
    }

    /// `dimmed` is the far route line's color, darker but still opaque.
    static func color(cycle: Double, dimmed: Bool = false) -> Color {
        var hue = cycle.truncatingRemainder(dividingBy: 1)
        if hue < 0 { hue += 1 }
        return Color(hue: hue, saturation: 0.85, brightness: dimmed ? 0.5 : 1)
    }

    struct MapSegment {
        let id: Int
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
    }

    /// Solid-color polylines for MapKit, one per small step of hue. MapKit
    /// doesn't lay a gradient along a polyline's length, so the fade is built
    /// from steps small enough to read as smooth. Step `k` always covers the
    /// same stretch of route, so it keeps its id, shape and color as the rider
    /// moves and MapKit only has to add or drop pieces at the ends. Each piece
    /// is clipped to `range`.
    static func mapSegments(along points: [ProcessedPoint], steps: [Int], clampedTo range: ClosedRange<Double>,
                            defaultZoom: Double, stepsPerCycle: Int, dimmed: Bool) -> [MapSegment] {
        guard points.count >= 2 else { return [] }
        let step = routeWavelength(defaultZoom: defaultZoom) / Double(stepsPerCycle)
        return steps.compactMap { k in
            let a = max(Double(k) * step, range.lowerBound)
            let b = min(Double(k + 1) * step, range.upperBound)
            guard b > a else { return nil }
            var i = index(atOrBefore: a, in: points)
            var coordinates = [coordinate(at: a, in: points, hint: &i)]
            var j = i + 1
            while j < points.count && points[j].distanceFromStart < b {
                coordinates.append(points[j].coordinate)
                j += 1
            }
            var h = min(max(j - 1, 0), points.count - 2)
            coordinates.append(coordinate(at: b, in: points, hint: &h))
            let hue = (Double(k) + 0.5) / Double(stepsPerCycle)
            return MapSegment(id: k, coordinates: coordinates, color: color(cycle: hue, dimmed: dimmed))
        }
    }

    private struct TrailKey: Equatable {
        let start: Date?
        let count: Int
        let stepsPerCycle: Int
    }

    private static var trailSegmentsKey: TrailKey?
    private static var cachedTrailSegments: [MapSegment] = []

    /// Free-ride trail as MapKit polylines, one per small step of hue, thinned
    /// to about 500 points like the canvas. Only rebuilt when the trail grows.
    static func trailMapSegments(_ trail: [CLLocation], stepsPerCycle: Int = 24) -> [MapSegment] {
        let key = TrailKey(start: trail.first?.timestamp, count: trail.count, stepsPerCycle: stepsPerCycle)
        if key != trailSegmentsKey {
            cachedTrailSegments = buildTrailMapSegments(trail, stepsPerCycle: stepsPerCycle)
            trailSegmentsKey = key
        }
        return cachedTrailSegments
    }

    private static func buildTrailMapSegments(_ trail: [CLLocation], stepsPerCycle: Int) -> [MapSegment] {
        guard trail.count >= 2 else { return [] }
        let cycles = cycles(for: trail)
        let every = max(1, trail.count / 500)
        var indices = Array(Swift.stride(from: 0, to: trail.count, by: every))
        if indices.last != trail.count - 1 { indices.append(trail.count - 1) }
        let perCycle = Double(stepsPerCycle)
        var segments: [MapSegment] = []
        var coordinates = [trail[indices[0]].coordinate]
        var step = Int((cycles[indices[0]] * perCycle).rounded(.down))
        for i in indices.dropFirst() {
            coordinates.append(trail[i].coordinate)
            let next = Int((cycles[i] * perCycle).rounded(.down))
            if next != step || i == trail.count - 1 {
                segments.append(MapSegment(
                    id: segments.count, coordinates: coordinates,
                    color: color(cycle: (Double(step) + 0.5) / perCycle)))
                coordinates = [trail[i].coordinate]
                step = next
            }
        }
        return segments
    }

    /// Index of the last point at or before `distance`, kept to a valid segment start.
    static func index(atOrBefore distance: Double, in points: [ProcessedPoint]) -> Int {
        var lo = 0, hi = points.count - 1
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if points[mid].distanceFromStart <= distance { lo = mid } else { hi = mid - 1 }
        }
        return min(lo, points.count - 2)
    }

    private static func coordinate(at distance: Double, in points: [ProcessedPoint],
                                   hint i: inout Int) -> CLLocationCoordinate2D {
        while i < points.count - 2 && points[i + 1].distanceFromStart < distance { i += 1 }
        let a = points[i], b = points[i + 1]
        let span = b.distanceFromStart - a.distanceFromStart
        let t = span > 0 ? min(max((distance - a.distanceFromStart) / span, 0), 1) : 0
        return CLLocationCoordinate2D(
            latitude: a.coordinate.latitude + (b.coordinate.latitude - a.coordinate.latitude) * t,
            longitude: a.coordinate.longitude + (b.coordinate.longitude - a.coordinate.longitude) * t)
    }

    private static var trailCycles: [Double] = []
    private static var trailStart: Date?

    /// Hue position of every trail point. The trail only grows during a ride,
    /// so new points are added onto the cached values instead of redoing the
    /// whole ride each redraw.
    static func cycles(for trail: [CLLocation]) -> [Double] {
        if trail.first?.timestamp != trailStart || trail.count < trailCycles.count {
            trailCycles = []
            trailStart = trail.first?.timestamp
        }
        guard !trail.isEmpty else { return [] }
        if trailCycles.isEmpty { trailCycles.append(0) }
        for i in trailCycles.count..<trail.count {
            let a = trail[i - 1], b = trail[i]
            let meters = b.distance(from: a)
            let dt = b.timestamp.timeIntervalSince(a.timestamp)
            let speed = b.speed >= 0 ? b.speed : (dt > 0 ? meters / dt : 0)
            // Cap GPS spikes so one bad fix can't spin through the whole rainbow.
            trailCycles.append(trailCycles[i - 1] + meters * min(speed, 25) / trailCycleConstant)
        }
        return trailCycles
    }

    /// Strokes a line that fades through the rainbow along its length. The line
    /// is drawn in short chunks, each with a linear gradient between its end
    /// colors. A chunk only covers a small slice of hue, so the result reads
    /// as one continuous fade.
    static func stroke(_ vertices: [Vertex], in context: GraphicsContext, style: StrokeStyle,
                       dimmed: Bool = false) {
        guard vertices.count >= 2 else { return }
        let step = 1.0 / 24

        func draw(_ path: Path, from a: Vertex, to b: Vertex) {
            let gradient = Gradient(colors: [color(cycle: a.cycle, dimmed: dimmed),
                                             color(cycle: b.cycle, dimmed: dimmed)])
            context.stroke(path, with: .linearGradient(gradient, startPoint: a.point, endPoint: b.point),
                           style: style)
        }

        var chunkStart = vertices[0]
        var chunk = Path()
        chunk.move(to: chunkStart.point)
        var chunkOpen = false
        var last = chunkStart

        for v in vertices.dropFirst() {
            // Split long straight segments so the hue can't skip across them.
            let span = v.cycle - last.cycle
            let pieces = max(1, Int((abs(span) / step).rounded(.up)))
            for k in 1...pieces {
                let t = Double(k) / Double(pieces)
                let p = Vertex(
                    point: CGPoint(x: last.point.x + (v.point.x - last.point.x) * t,
                                   y: last.point.y + (v.point.y - last.point.y) * t),
                    cycle: last.cycle + span * t)
                chunk.addLine(to: p.point)
                chunkOpen = true
                if abs(p.cycle - chunkStart.cycle) >= step {
                    draw(chunk, from: chunkStart, to: p)
                    chunkStart = p
                    chunk = Path()
                    chunk.move(to: p.point)
                    chunkOpen = false
                }
            }
            last = v
        }
        if chunkOpen {
            draw(chunk, from: chunkStart, to: last)
        }
    }
}

// MARK: - Free ride framing

/// What a free ride's overview frames: the trail and the rider, never
/// tighter than `minSpan` metres. A new ride has no trail until it sets off,
/// so the map and the rider still show while waiting.
struct FreeRideFrame {
    let minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

    static let minSpan: Double = 200

    var center: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: (minLat + maxLat) / 2, longitude: (minLon + maxLon) / 2)
    }

    init?(trail: [CLLocation], current: CLLocation?) {
        var trailBounds = Self.trailBounds(trail)
        if let current {
            trailBounds = trailBounds?.including(current.coordinate) ?? Bounds(current.coordinate)
        }
        guard let bounds = trailBounds else { return nil }
        var minLat = bounds.minLat, maxLat = bounds.maxLat
        var minLon = bounds.minLon, maxLon = bounds.maxLon
        let metresPerDegree = 111_320.0
        let minLatSpan = Self.minSpan / metresPerDegree
        let cosLat = max(cos((minLat + maxLat) / 2 * .pi / 180), 0.01)
        let minLonSpan = minLatSpan / cosLat
        if maxLat - minLat < minLatSpan {
            let mid = (minLat + maxLat) / 2
            minLat = mid - minLatSpan / 2
            maxLat = mid + minLatSpan / 2
        }
        if maxLon - minLon < minLonSpan {
            let mid = (minLon + maxLon) / 2
            minLon = mid - minLonSpan / 2
            maxLon = mid + minLonSpan / 2
        }
        self.minLat = minLat
        self.maxLat = maxLat
        self.minLon = minLon
        self.maxLon = maxLon
    }

    private struct Bounds {
        var minLat: Double, maxLat: Double, minLon: Double, maxLon: Double

        init(_ c: CLLocationCoordinate2D) {
            minLat = c.latitude
            maxLat = c.latitude
            minLon = c.longitude
            maxLon = c.longitude
        }

        func including(_ c: CLLocationCoordinate2D) -> Bounds {
            var b = self
            b.minLat = min(b.minLat, c.latitude)
            b.maxLat = max(b.maxLat, c.latitude)
            b.minLon = min(b.minLon, c.longitude)
            b.maxLon = max(b.maxLon, c.longitude)
            return b
        }
    }

    private static var boundsStart: Date?
    private static var boundsCount = 0
    private static var cachedBounds: Bounds?

    /// The trail only grows during a ride, so new points widen the cached box
    /// instead of rescanning the whole ride each redraw.
    private static func trailBounds(_ trail: [CLLocation]) -> Bounds? {
        if trail.first?.timestamp != boundsStart || trail.count < boundsCount {
            boundsStart = trail.first?.timestamp
            boundsCount = 0
            cachedBounds = nil
        }
        for location in trail[boundsCount...] {
            cachedBounds = cachedBounds?.including(location.coordinate) ?? Bounds(location.coordinate)
        }
        boundsCount = trail.count
        return cachedBounds
    }
}

// MARK: - Full route canvas

/// Renders the entire planned route (or recorded free-ride trail) fitted to
/// the view, with completed portion in green, mile markers, POIs, and a
/// rider dot at the current location.
struct RouteMapFullRouteCanvas: View {
    let data: RouteMapData
    var routeAheadColor: RouteColor = .white

    @ObservedObject private var unitState = UnitState.shared

    var body: some View {
        let _ = unitState.preferences // dependency for Canvas redraws on unit change
        Canvas { context, size in
            // Safe area insets for watch: top/bottom for rounded corners + UI overlays
            let insetTop: CGFloat = 36
            let insetBottom: CGFloat = 20
            let insetSide: CGFloat = 16

            if let processed = data.processedRoute {
                let points = processed.points
                guard points.count >= 2 else { return }

                let transform = makeTransform(
                    minLat: processed.minLat, maxLat: processed.maxLat,
                    minLon: processed.minLon, maxLon: processed.maxLon,
                    size: size, insetTop: insetTop, insetBottom: insetBottom, insetSide: insetSide)
                let stride = max(1, points.count / 500)

                var path = Path()
                path.move(to: project(points[0].coordinate, transform: transform))
                for i in Swift.stride(from: 1, to: points.count, by: stride) {
                    path.addLine(to: project(points[i].coordinate, transform: transform))
                }
                path.addLine(to: project(points[points.count - 1].coordinate, transform: transform))
                context.stroke(path, with: .color(.gray),
                               style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

                let segIdx = data.currentSegmentIndex
                if segIdx > 0 {
                    var done = Path()
                    done.move(to: project(points[0].coordinate, transform: transform))
                    let doneStride = max(1, segIdx / 300)
                    for i in Swift.stride(from: 1, through: min(segIdx, points.count - 1), by: doneStride) {
                        done.addLine(to: project(points[i].coordinate, transform: transform))
                    }
                    done.addLine(to: project(points[min(segIdx, points.count - 1)].coordinate, transform: transform))
                    context.stroke(done, with: .color(.riddenRoute),
                                   style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
                }

                // Mile markers — auto-pick interval so long routes don't get
                // overcrowded.
                let interval = autoMileMarkerInterval(totalMeters: processed.totalDistance)
                let markers = computeMileMarkers(points: points, interval: interval)
                for marker in markers {
                    let pt = project(marker.coordinate, transform: transform)
                    let dir: CGFloat = -1
                    let poleTip = CGPoint(x: pt.x, y: pt.y + 10 * dir)
                    let flagMid = CGPoint(x: pt.x, y: pt.y + 6 * dir)
                    let flagOuter = CGPoint(x: pt.x + 7, y: pt.y + 8 * dir)
                    let labelPt = CGPoint(x: pt.x + 4, y: pt.y + 14 * dir)
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: pt.x, y: pt.y))
                            p.addLine(to: poleTip)
                        },
                        with: .color(.orange),
                        style: StrokeStyle(lineWidth: 1.5))
                    context.fill(
                        Path { p in
                            p.move(to: poleTip)
                            p.addLine(to: flagOuter)
                            p.addLine(to: flagMid)
                            p.closeSubpath()
                        },
                        with: .color(.orange))
                    let text = Text("\(marker.mile)")
                        .font(.system(size: 7, weight: .bold))
                        .foregroundColor(.white)
                    context.draw(context.resolve(text), at: labelPt)
                }

                // POI pins (full route view)
                if data.showWaypointsOnRouteMap {
                    for poi in processed.pois {
                        let pt = project(poi.coordinate, transform: transform)
                        drawWaypointPin(context: context, at: pt, scale: 0.85)
                    }
                }

                if let loc = data.currentLocation {
                    let pos = project(loc.coordinate, transform: transform)
                    if data.isOffRoute {
                        let candidates = data.rejoinCandidateCoords
                        if candidates.isEmpty {
                            let nearIdx = data.currentSegmentIndex
                            let nearPt = project(points[min(nearIdx, points.count - 1)].coordinate, transform: transform)
                            var returnLine = Path()
                            returnLine.move(to: pos)
                            returnLine.addLine(to: nearPt)
                            context.stroke(returnLine, with: .color(.red),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                        } else {
                            for (i, candidate) in candidates.enumerated() {
                                let candidatePt = project(candidate, transform: transform)
                                var returnLine = Path()
                                returnLine.move(to: pos)
                                returnLine.addLine(to: candidatePt)
                                let opacity = i == 0 ? 1.0 : 0.6
                                context.stroke(returnLine, with: .color(.red.opacity(opacity)),
                                               style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                                context.fill(
                                    Path(ellipseIn: CGRect(x: candidatePt.x - 3, y: candidatePt.y - 3, width: 6, height: 6)),
                                    with: .color(.red.opacity(0.4 * opacity)))
                            }
                        }

                        context.fill(Path(ellipseIn: CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)), with: .color(.red.opacity(0.3)))
                        context.fill(Path(ellipseIn: CGRect(x: pos.x - 3.5, y: pos.y - 3.5, width: 7, height: 7)), with: .color(.red))
                    } else {
                        context.fill(Path(ellipseIn: CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)), with: .color(.white))
                        context.fill(Path(ellipseIn: CGRect(x: pos.x - 3.5, y: pos.y - 3.5, width: 7, height: 7)), with: .color(.blue))
                    }
                }
            } else {
                // Free ride: the whole recorded trail and the rider
                let trail = data.recordedLocations
                guard let frame = FreeRideFrame(trail: trail, current: data.currentLocation) else { return }

                let transform = makeTransform(
                    minLat: frame.minLat, maxLat: frame.maxLat,
                    minLon: frame.minLon, maxLon: frame.maxLon,
                    size: size, insetTop: insetTop, insetBottom: insetBottom, insetSide: insetSide)
                let stride = max(1, trail.count / 500)

                let trailStyle = StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round)
                // A new ride has no trail until it sets off, just the rider.
                let hasTrail = trail.count >= 2
                if hasTrail && routeAheadColor == .rainbow {
                    var indices = Array(Swift.stride(from: 0, to: trail.count, by: stride))
                    if indices.last != trail.count - 1 { indices.append(trail.count - 1) }
                    let cycles = RouteRainbow.cycles(for: trail)
                    let vertices = indices.map {
                        RouteRainbow.Vertex(point: project(trail[$0].coordinate, transform: transform),
                                            cycle: cycles[$0])
                    }
                    RouteRainbow.stroke(vertices, in: context, style: trailStyle)
                } else if hasTrail {
                    var path = Path()
                    path.move(to: project(trail[0].coordinate, transform: transform))
                    for i in Swift.stride(from: 1, to: trail.count, by: stride) {
                        path.addLine(to: project(trail[i].coordinate, transform: transform))
                    }
                    path.addLine(to: project(trail[trail.count - 1].coordinate, transform: transform))
                    context.stroke(path, with: .color(routeAheadColor.color), style: trailStyle)
                }

                if let loc = data.currentLocation {
                    let pos = project(loc.coordinate, transform: transform)
                    context.fill(Path(ellipseIn: CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)), with: .color(.white))
                    context.fill(Path(ellipseIn: CGRect(x: pos.x - 3.5, y: pos.y - 3.5, width: 7, height: 7)), with: .color(.blue))
                }
            }
        }
    }

    private struct MapTransform {
        let offsetX: Double, offsetY: Double, scale: Double, cosLat: Double
    }

    private func makeTransform(minLat: Double, maxLat: Double, minLon: Double, maxLon: Double,
                               size: CGSize, insetTop: CGFloat, insetBottom: CGFloat, insetSide: CGFloat) -> MapTransform {
        let centerLat = (minLat + maxLat) / 2
        let cosLat = cos(centerLat * .pi / 180)
        let latSpan = maxLat - minLat
        let lonSpan = (maxLon - minLon) * cosLat
        let drawW = Double(size.width - insetSide * 2)
        let drawH = Double(size.height - insetTop - insetBottom)
        let scale = (latSpan == 0 && lonSpan == 0) ? 1 : min(drawW / lonSpan, drawH / latSpan)
        let midLon = (minLon + maxLon) / 2
        let midLat = (minLat + maxLat) / 2
        let centerX = Double(insetSide) + drawW / 2
        let centerY = Double(insetTop) + drawH / 2
        return MapTransform(
            offsetX: centerX - midLon * cosLat * scale,
            offsetY: centerY + midLat * scale,
            scale: scale, cosLat: cosLat)
    }

    private func project(_ coord: CLLocationCoordinate2D, transform: MapTransform) -> CGPoint {
        CGPoint(
            x: coord.longitude * transform.cosLat * transform.scale + transform.offsetX,
            y: -coord.latitude * transform.scale + transform.offsetY)
    }
}

// MARK: - Breadcrumb canvas

/// Rider-centered, zoomed Canvas view. `viewDistance` controls how many
/// meters of route appear ahead of the rider (lower = more zoomed in).
struct RouteMapBreadcrumbCanvas: View {
    let data: RouteMapData
    let viewDistance: Double
    var useCompassHeading: Bool = true
    var routeAheadColor: RouteColor = .white
    /// Sets the rainbow's cycle length. See `RouteRainbow.routeWavelength`.
    var defaultZoom: Double = 400
    /// When true, runs a TimelineView ticker to re-render at ~10Hz. The phone
    /// preview is static so it disables this.
    var animated: Bool = true

    @ObservedObject private var unitState = UnitState.shared

    var body: some View {
        let _ = unitState.preferences
        if animated {
            TimelineView(.periodic(from: .now, by: 0.1)) { _ in
                canvas
            }
        } else {
            canvas
        }
    }

    private var canvas: some View {
        Canvas { context, size in
            draw(context: &context, size: size)
        }
    }

    private func draw(context: inout GraphicsContext, size: CGSize) {
        guard let location = data.currentLocation else { return }

        // Free ride: draw rider trail only
        if data.processedRoute == nil {
            let riderScreenX = size.width / 2
            let riderScreenY = size.height * 0.75
            let metersPerPx = min(size.width, size.height) / viewDistance

            let center = location.coordinate
            let cosLat = cos(center.latitude * .pi / 180)

            let bearing: Double
            if useCompassHeading, data.heading > 0 {
                bearing = data.heading
            } else if location.course >= 0 {
                bearing = location.course
            } else {
                bearing = 0
            }
            let rotRad = bearing * .pi / 180

            func toScreen(_ coord: CLLocationCoordinate2D) -> CGPoint {
                let dx = (coord.longitude - center.longitude) * cosLat * 111_320
                let dy = (coord.latitude - center.latitude) * 111_320
                let rx = dx * cos(rotRad) - dy * sin(rotRad)
                let ry = dx * sin(rotRad) + dy * cos(rotRad)
                return CGPoint(
                    x: riderScreenX + rx * metersPerPx,
                    y: riderScreenY - ry * metersPerPx)
            }

            let trail = data.recordedLocations
            if trail.count >= 2 {
                let viewMeters = viewDistance * 2
                var path = Path()
                var started = false
                for loc in trail {
                    let dist = location.distance(from: loc)
                    guard dist < viewMeters else { continue }
                    let pt = toScreen(loc.coordinate)
                    if !started {
                        path.move(to: pt)
                        started = true
                    } else {
                        path.addLine(to: pt)
                    }
                }
                context.stroke(path, with: .color(.green.opacity(0.6)),
                               style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }

            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 8, y: riderScreenY - 8, width: 16, height: 16)),
                with: .color(.white))
            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 6, y: riderScreenY - 6, width: 12, height: 12)),
                with: .color(.blue))
            return
        }

        guard let processed = data.processedRoute else { return }
        let points = processed.points
        let segIdx = data.currentSegmentIndex
        guard points.count >= 2, segIdx < points.count else { return }

        let currentDist = data.distanceAlongRoute

        let bearing: Double
        if useCompassHeading, data.heading > 0 {
            bearing = data.heading
        } else if data.speed > 1.0, location.course >= 0 {
            bearing = location.course
        } else {
            bearing = processed.points[segIdx].bearingToNext
        }

        let riderScreenX = size.width / 2
        let riderScreenY = size.height * 0.75
        let metersPerPx = min(size.width, size.height) / viewDistance

        let window = (currentDist - RouteLineLayout.nearBehind(viewDistance))...(currentDist + RouteLineLayout.nearAhead(viewDistance))

        let center = location.coordinate
        let cosLat = cos(center.latitude * .pi / 180)
        let rotRad = bearing * .pi / 180

        func toScreen(_ coord: CLLocationCoordinate2D) -> CGPoint {
            let dx = (coord.longitude - center.longitude) * cosLat * 111_320
            let dy = (coord.latitude - center.latitude) * 111_320
            let rx = dx * cos(rotRad) - dy * sin(rotRad)
            let ry = dx * sin(rotRad) + dy * cos(rotRad)
            return CGPoint(
                x: riderScreenX + rx * metersPerPx,
                y: riderScreenY - ry * metersPerPx)
        }

        let screenW = Double(size.width)
        let screenH = Double(size.height)
        let rainbow = routeAheadColor == .rainbow
        let lastIdx = points.count - 1

        // The thick window as an index range around the rider. The thin far
        // sections start and end on these exact points so the two always meet.
        var firstNear = segIdx
        while firstNear > 0 && points[firstNear - 1].distanceFromStart >= window.lowerBound { firstNear -= 1 }
        var lastNear = segIdx
        while lastNear < lastIdx && points[lastNear + 1].distanceFromStart <= window.upperBound { lastNear += 1 }

        func vertex(_ i: Int) -> RouteRainbow.Vertex {
            RouteRainbow.Vertex(
                point: toScreen(points[i].coordinate),
                cycle: RouteRainbow.routeCycle(at: points[i].distanceFromStart, defaultZoom: defaultZoom))
        }

        func path(_ vertices: [RouteRainbow.Vertex]) -> Path {
            var p = Path()
            guard let first = vertices.first else { return p }
            p.move(to: first.point)
            for v in vertices.dropFirst() { p.addLine(to: v.point) }
            return p
        }

        // Splits a far section into the runs that touch the screen, so long
        // routes don't stroke thousands of offscreen segments.
        let visibleRect = CGRect(origin: .zero, size: size).insetBy(dx: -60, dy: -60)
        func visibleRuns(_ indices: [Int]) -> [[RouteRainbow.Vertex]] {
            var runs: [[RouteRainbow.Vertex]] = []
            var run: [RouteRainbow.Vertex] = []
            var prev: RouteRainbow.Vertex?
            for i in indices {
                let v = vertex(i)
                if let p = prev {
                    let bounds = CGRect(x: min(p.point.x, v.point.x), y: min(p.point.y, v.point.y),
                                        width: abs(p.point.x - v.point.x), height: abs(p.point.y - v.point.y))
                        .insetBy(dx: -1, dy: -1)
                    if bounds.intersects(visibleRect) {
                        if run.isEmpty { run.append(p) }
                        run.append(v)
                    } else if !run.isEmpty {
                        runs.append(run)
                        run = []
                    }
                }
                prev = v
            }
            if !run.isEmpty { runs.append(run) }
            return runs
        }

        // Thick window points, skipping ones under 2px apart. The window's end
        // points always stay so the far lines join exactly.
        func nearVertices(_ range: ClosedRange<Int>) -> [RouteRainbow.Vertex] {
            var out: [RouteRainbow.Vertex] = []
            for i in range {
                let v = vertex(i)
                if let last = out.last, i != range.upperBound,
                   abs(v.point.x - last.point.x) + abs(v.point.y - last.point.y) < 2 { continue }
                out.append(v)
            }
            return out
        }

        let visStride = max(1, points.count / 800)
        let farStyle = StrokeStyle(lineWidth: RouteLineLayout.farLineWidth, lineCap: .round, lineJoin: .round)
        let nearStyle = StrokeStyle(lineWidth: RouteLineLayout.nearLineWidth, lineCap: .round, lineJoin: .round)

        // Far sections first, thin, so the thick window draws over their ends.
        if firstNear > 0 {
            let indices = Array(Swift.stride(from: 0, to: firstNear, by: visStride)) + [firstNear]
            for run in visibleRuns(indices) {
                context.stroke(path(run), with: .color(.riddenRoute.opacity(0.6)), style: farStyle)
            }
        }
        if lastNear < lastIdx {
            let indices = Array(Swift.stride(from: lastNear, to: lastIdx, by: visStride)) + [lastIdx]
            for run in visibleRuns(indices) {
                if rainbow {
                    RouteRainbow.stroke(run, in: context, style: farStyle, dimmed: true)
                } else {
                    context.stroke(path(run), with: .color(routeAheadColor.color.opacity(RouteLineLayout.farOpacity)),
                                   style: farStyle)
                }
            }
        }

        let split = min(max(segIdx, firstNear), lastNear)
        context.stroke(path(nearVertices(firstNear...split)), with: .color(.riddenRoute), style: nearStyle)
        let aheadVertices = nearVertices(split...lastNear)
        if rainbow {
            RouteRainbow.stroke(aheadVertices, in: context, style: nearStyle)
        } else {
            context.stroke(path(aheadVertices), with: .color(routeAheadColor.color), style: nearStyle)
        }

        // POI pins (breadcrumb view)
        if data.showWaypointsOnRouteMap {
            for poi in processed.pois {
                let pt = toScreen(poi.coordinate)
                guard pt.x >= -10 && pt.x <= screenW + 10 &&
                      pt.y >= -10 && pt.y <= screenH + 10 else { continue }
                drawWaypointPin(context: context, at: pt, scale: 1.1)
            }
        }

        // Mile markers — cached so the TimelineView ticker doesn't recompute
        // them every frame on long routes.
        let markers = MileMarkerCache.markers(for: points)
        for marker in markers {
            let pt = toScreen(marker.coordinate)
            guard pt.x >= -10 && pt.x <= screenW + 10 &&
                  pt.y >= -10 && pt.y <= screenH + 10 else { continue }
            let dir: CGFloat = -1
            let poleTip = CGPoint(x: pt.x, y: pt.y + 12 * dir)
            let flagMid = CGPoint(x: pt.x, y: pt.y + 7 * dir)
            let flagOuter = CGPoint(x: pt.x + 8, y: pt.y + 9.5 * dir)
            let labelPt = CGPoint(x: pt.x + 5, y: pt.y + 16 * dir)
            context.stroke(
                Path { p in
                    p.move(to: CGPoint(x: pt.x, y: pt.y))
                    p.addLine(to: poleTip)
                },
                with: .color(.orange),
                style: StrokeStyle(lineWidth: 1.5))
            context.fill(
                Path { p in
                    p.move(to: poleTip)
                    p.addLine(to: flagOuter)
                    p.addLine(to: flagMid)
                    p.closeSubpath()
                },
                with: .color(.orange))
            let text = Text("\(marker.mile)")
                .font(.system(size: 8, weight: .bold))
                .foregroundColor(.white)
            context.draw(context.resolve(text), at: labelPt)
        }

        if data.isOffRoute {
            let trail = data.recordedLocations
            if trail.count >= 2 {
                let viewMeters = viewDistance * 2
                var trailPath = Path()
                var started = false
                var lastPt = CGPoint.zero
                for loc in trail {
                    let dist = location.distance(from: loc)
                    guard dist < viewMeters else { continue }
                    let pt = toScreen(loc.coordinate)
                    if started && abs(pt.x - lastPt.x) + abs(pt.y - lastPt.y) < 2 { continue }
                    if !started {
                        trailPath.move(to: pt)
                        started = true
                    } else {
                        trailPath.addLine(to: pt)
                    }
                    lastPt = pt
                }
                context.stroke(trailPath, with: .color(.orange.opacity(0.7)),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }
        }

        if data.isOffRoute {
            let candidates = data.rejoinCandidateCoords
            if candidates.isEmpty {
                let nearestCoord = points[min(segIdx, points.count - 1)].coordinate
                let nearestScreen = toScreen(nearestCoord)

                var returnLine = Path()
                returnLine.move(to: CGPoint(x: riderScreenX, y: riderScreenY))
                returnLine.addLine(to: nearestScreen)
                context.stroke(returnLine, with: .color(.red),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, dash: [8, 5]))

                context.fill(
                    Path(ellipseIn: CGRect(x: nearestScreen.x - 4, y: nearestScreen.y - 4, width: 8, height: 8)),
                    with: .color(.red.opacity(0.5)))
            } else {
                for (i, candidate) in candidates.enumerated() {
                    let candidateScreen = toScreen(candidate)
                    var returnLine = Path()
                    returnLine.move(to: CGPoint(x: riderScreenX, y: riderScreenY))
                    returnLine.addLine(to: candidateScreen)
                    let opacity = i == 0 ? 1.0 : 0.5
                    let lineWidth: CGFloat = i == 0 ? 3 : 2
                    context.stroke(returnLine, with: .color(.red.opacity(opacity)),
                                   style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, dash: [8, 5]))

                    let dotSize: CGFloat = i == 0 ? 8 : 6
                    context.fill(
                        Path(ellipseIn: CGRect(
                            x: candidateScreen.x - dotSize / 2,
                            y: candidateScreen.y - dotSize / 2,
                            width: dotSize, height: dotSize)),
                        with: .color(.red.opacity(0.5 * opacity)))
                }
            }

            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 8, y: riderScreenY - 8, width: 16, height: 16)),
                with: .color(.red.opacity(0.3)))
            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 6, y: riderScreenY - 6, width: 12, height: 12)),
                with: .color(.red))
        } else {
            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 8, y: riderScreenY - 8, width: 16, height: 16)),
                with: .color(.white))
            context.fill(
                Path(ellipseIn: CGRect(x: riderScreenX - 6, y: riderScreenY - 6, width: 12, height: 12)),
                with: .color(.blue))
        }
    }
}

// MARK: - Waypoint pin (shared)

func drawRouteMapWaypointPin(context: GraphicsContext, at pt: CGPoint, scale: CGFloat = 1.0) {
    drawWaypointPin(context: context, at: pt, scale: scale)
}

// Cache for mile markers in the breadcrumb canvas so the 10Hz TimelineView
// doesn't recompute them every tick on long routes.
private enum MileMarkerCache {
    private static var lastCount: Int = -1
    private static var lastUnit: DistanceUnit = .miles
    private static var cachedMarkers: [MileMarker] = []

    static func markers(for points: [ProcessedPoint]) -> [MileMarker] {
        let count = points.count
        let unit = currentUnits.distance
        if count != lastCount || unit != lastUnit {
            cachedMarkers = computeMileMarkers(points: points)
            lastCount = count
            lastUnit = unit
        }
        return cachedMarkers
    }
}

fileprivate func drawWaypointPin(context: GraphicsContext, at pt: CGPoint, scale: CGFloat = 1.0) {
    let radius: CGFloat = 3 * scale
    let stemLength: CGFloat = 6 * scale
    // Stem
    context.stroke(
        Path { p in
            p.move(to: CGPoint(x: pt.x, y: pt.y))
            p.addLine(to: CGPoint(x: pt.x, y: pt.y - stemLength))
        },
        with: .color(.orange),
        style: StrokeStyle(lineWidth: 1.5 * scale, lineCap: .round))
    // Head
    context.fill(
        Path(ellipseIn: CGRect(
            x: pt.x - radius,
            y: pt.y - stemLength - radius,
            width: radius * 2,
            height: radius * 2)),
        with: .color(.orange))
    // Inner dot
    context.fill(
        Path(ellipseIn: CGRect(
            x: pt.x - radius * 0.45,
            y: pt.y - stemLength - radius * 0.45,
            width: radius * 0.9,
            height: radius * 0.9)),
        with: .color(.white))
}

#Preview("Free ride, waiting to set off") {
    RouteMapFullRouteCanvas(
        data: RouteMapData(currentLocation: CLLocation(latitude: 42.3398, longitude: -71.0892)))
        .frame(width: 198, height: 242)
        .background(.black)
}

#Preview("Free ride, just set off") {
    let start = CLLocationCoordinate2D(latitude: 42.3398, longitude: -71.0892)
    let trail = (0..<12).map {
        CLLocation(latitude: start.latitude + Double($0) * 0.00004, longitude: start.longitude + Double($0) * 0.00003)
    }
    return RouteMapFullRouteCanvas(
        data: RouteMapData(currentLocation: trail.last, recordedLocations: trail))
        .frame(width: 198, height: 242)
        .background(.black)
}
