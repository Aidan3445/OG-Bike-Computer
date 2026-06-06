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
                    context.stroke(done, with: .color(.green),
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
                // Free ride: show entire recorded path
                let trail = data.recordedLocations
                guard trail.count >= 2 else { return }

                var minLat = Double.greatestFiniteMagnitude, maxLat = -Double.greatestFiniteMagnitude
                var minLon = Double.greatestFiniteMagnitude, maxLon = -Double.greatestFiniteMagnitude
                for loc in trail {
                    let c = loc.coordinate
                    if c.latitude < minLat { minLat = c.latitude }
                    if c.latitude > maxLat { maxLat = c.latitude }
                    if c.longitude < minLon { minLon = c.longitude }
                    if c.longitude > maxLon { maxLon = c.longitude }
                }

                let transform = makeTransform(
                    minLat: minLat, maxLat: maxLat,
                    minLon: minLon, maxLon: maxLon,
                    size: size, insetTop: insetTop, insetBottom: insetBottom, insetSide: insetSide)
                let stride = max(1, trail.count / 500)

                var path = Path()
                path.move(to: project(trail[0].coordinate, transform: transform))
                for i in Swift.stride(from: 1, to: trail.count, by: stride) {
                    path.addLine(to: project(trail[i].coordinate, transform: transform))
                }
                path.addLine(to: project(trail[trail.count - 1].coordinate, transform: transform))
                context.stroke(path, with: .color(routeAheadColor.color),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

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
    /// When true, runs a TimelineView ticker to re-render at ~10Hz. The phone
    /// preview is static so it disables this.
    var animated: Bool = true

    @ObservedObject private var unitState = UnitState.shared

    private let routeLineWidth: CGFloat = 6

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

        let behind = viewDistance * 1.0
        let ahead = viewDistance * 2.5
        let minDist = currentDist - behind
        let maxDist = currentDist + ahead

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

        // Distant sections first (dimmer)
        let screenW = Double(size.width)
        let screenH = Double(size.height)
        let margin: Double = 60
        let visStride = max(1, points.count / 800)

        var distantGrayPath = Path()
        var distantGrayStarted = false
        var distantGreenPath = Path()
        var distantGreenStarted = false

        for i in Swift.stride(from: 0, to: points.count, by: visStride) {
            let point = points[i]

            if point.distanceFromStart >= minDist - 200 && point.distanceFromStart <= maxDist + 200 {
                if distantGrayStarted { distantGrayStarted = false }
                if distantGreenStarted { distantGreenStarted = false }
                continue
            }

            let pt = toScreen(point.coordinate)

            guard pt.x >= -margin && pt.x <= screenW + margin &&
                  pt.y >= -margin && pt.y <= screenH + margin else {
                if distantGrayStarted { distantGrayStarted = false }
                if distantGreenStarted { distantGreenStarted = false }
                continue
            }

            if point.distanceFromStart <= currentDist {
                if distantGrayStarted { distantGrayStarted = false }
                if !distantGreenStarted {
                    distantGreenPath.move(to: pt)
                    distantGreenStarted = true
                } else {
                    distantGreenPath.addLine(to: pt)
                }
            } else {
                if distantGreenStarted { distantGreenStarted = false }
                if !distantGrayStarted {
                    distantGrayPath.move(to: pt)
                    distantGrayStarted = true
                } else {
                    distantGrayPath.addLine(to: pt)
                }
            }
        }

        context.stroke(distantGreenPath, with: .color(.green.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
        context.stroke(distantGrayPath, with: .color(.gray.opacity(0.4)),
                       style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))

        // Primary behind/ahead rendering
        var behindPath = Path()
        var aheadPath = Path()
        var startedBehind = false
        var startedAhead = false
        var lastSX: Double = .greatestFiniteMagnitude
        var lastSY: Double = .greatestFiniteMagnitude

        var bridgePoint: CGPoint?

        for point in points {
            guard point.distanceFromStart >= minDist - 200,
                  point.distanceFromStart <= maxDist + 200 else { continue }

            let pt = toScreen(point.coordinate)

            if abs(pt.x - lastSX) + abs(pt.y - lastSY) < 2 { continue }
            lastSX = pt.x
            lastSY = pt.y

            if point.distanceFromStart <= currentDist {
                if !startedBehind {
                    behindPath.move(to: pt)
                    startedBehind = true
                } else {
                    behindPath.addLine(to: pt)
                }
                bridgePoint = pt
            } else {
                if !startedAhead {
                    if let bp = bridgePoint {
                        aheadPath.move(to: bp)
                        aheadPath.addLine(to: pt)
                    } else {
                        aheadPath.move(to: pt)
                    }
                    startedAhead = true
                } else {
                    aheadPath.addLine(to: pt)
                }
            }
        }

        let style = StrokeStyle(lineWidth: routeLineWidth, lineCap: .round, lineJoin: .round)
        context.stroke(behindPath, with: .color(.green.opacity(0.4)), style: style)
        context.stroke(aheadPath, with: .color(routeAheadColor.color), style: style)

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
