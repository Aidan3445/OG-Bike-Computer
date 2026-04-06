//
//  RouteMapView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI
import CoreLocation

struct RouteMapView: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// When true, renders a stripped-down version for the metric screen turn overlay
    /// (no buttons, no stats, no heading — just route shape, orientation, and rider position)
    var isOverlay: Bool = false

    @State private var showFullRoute = false
    @State private var autoSwitchTask: Task<Void, Never>?

    @State private var zoomIndex: Int = -1 // -1 means "use default from config"
    private var mapConfig: MapScreenConfig { workout.ridePreferences.mapScreen }

    private var zoomLevels: [Double] { mapConfig.computedZoomLevels }

    private var effectiveZoomIndex: Int {
        if zoomIndex < 0 { return mapConfig.defaultZoomIndex }
        return min(zoomIndex, zoomLevels.count - 1)
    }

    var body: some View {
        ZStack {
            Group {
                if showFullRoute || !workout.hasRoute {
                    FullRouteCanvas(workout: workout, routeAheadColor: mapConfig.routeAheadColor)
                } else {
                    BreadcrumbCanvas(
                        workout: workout,
                        viewDistance: zoomLevels.isEmpty ? 400 : zoomLevels[effectiveZoomIndex],
                        useCompassHeading: workout.ridePreferences.mapRotation == .headingUp && !isLuminanceReduced,
                        routeAheadColor: mapConfig.routeAheadColor)
                }
            }
            .ignoresSafeArea()

            if !isOverlay {
                fullControls
            }
        }
        .onChange(of: isLuminanceReduced) { _, reduced in
            workout.setHeadingUpdates(enabled: !reduced)
         }
    }

    // MARK: - Full Controls (non-overlay mode)

    @ViewBuilder
    private var fullControls: some View {
        VStack(spacing: 0) {
            HStack(alignment: .top, spacing: 4) {
                if !showFullRoute {
                    statsOverlay
                }

                Spacer()

                VStack(spacing: 2) {
                    if workout.hasRoute && mapConfig.showFullRouteToggle {
                        Button {
                            showFullRoute.toggle()
                            if showFullRoute {
                                scheduleAutoSwitch()
                            } else {
                                autoSwitchTask?.cancel()
                            }
                        } label: {
                            Image(systemName: showFullRoute ? "scope" : "map")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                    }

                    if mapConfig.showHeading && workout.hasRoute {
                        Text(cardinalDirection)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
            }
            .padding(.horizontal, 4)
            .padding(.top, 0)

            Spacer()

            if !showFullRoute && workout.hasRoute {
                HStack(alignment: .bottom) {
                    Button {
                        let idx = effectiveZoomIndex
                        if idx < zoomLevels.count - 1 {
                            zoomIndex = idx + 1
                        }
                    } label: {
                        Image(systemName: "minus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .opacity(effectiveZoomIndex < zoomLevels.count - 1 ? 1 : 0.3)

                    Spacer()

                    Button {
                        let idx = effectiveZoomIndex
                        if idx > 0 {
                            zoomIndex = idx - 1
                        }
                    } label: {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .bold))
                            .frame(width: 36, height: 36)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .frame(width: 48, height: 48)
                    .contentShape(Rectangle())
                    .opacity(effectiveZoomIndex > 0 ? 1 : 0.3)
                }
            }
        }
    }

    // MARK: - Stats Overlay

    @ViewBuilder
    private var statsOverlay: some View {
        if workout.navigation.isOffRoute {
            VStack(spacing: 1) {
                Text("OFF ROUTE")
                    .font(.system(size: 11, weight: .heavy))
                    .foregroundStyle(.red)
                Text(formatTurnDistance(workout.navigation.nearestRouteDistance))
                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                    .foregroundStyle(.red.opacity(0.8))
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.red.opacity(0.15))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if workout.navigation.nextTurn != nil || !workout.hasRoute || mapConfig.primaryStat != .none || !mapConfig.secondaryStats.filter({ $0 != .none }).isEmpty {
            VStack(spacing: 1) {
                // Primary stat
                if mapConfig.primaryStat != .none {
                    let primary = resolveMapStat(mapConfig.primaryStat)
                    HStack(spacing: 2) {
                        Text(primary.value)
                            .font(.system(size: 14, weight: .bold, design: .rounded))
                            .monospacedDigit()
                        if let unit = primary.unit {
                            Text(unit)
                                .font(.system(size: 7))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Turn info
                if mapConfig.showTurnInfo, let turn = workout.navigation.nextTurn {
                    HStack(spacing: 4) {
                        Image(systemName: turn.direction.icon)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(.yellow)
                        Text(formatTurnDistance(workout.navigation.distanceToNextTurn))
                            .font(.system(size: 12, weight: .semibold, design: .rounded))
                            .monospacedDigit()
                    }
                }

                // Secondary stats (value + unit inline)
                ForEach(Array(mapConfig.secondaryStats.enumerated()), id: \.offset) { index, stat in
                    if stat != .none {
                        let resolved = resolveMapStat(stat)
                        let display = resolved.unit != nil ? "\(resolved.value) \(resolved.unit!)" : resolved.value
                        Text(display)
                            .font(.system(size: index == mapConfig.secondaryStats.count - 1 ? 9 : 10, weight: .semibold, design: .rounded))
                            .foregroundStyle(index == mapConfig.secondaryStats.count - 1 ? .secondary : .primary)
                    }
                }
            }
            .padding(.horizontal, 6)
            .padding(.vertical, 3)
            .background(.black.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    // MARK: - Stat Resolution

    private func resolveMapStat(_ type: MapStatType) -> (value: String, unit: String?) {
        switch type {
        case .speed:
            return (formatSpeed(workout.speed, false), currentUnits.speed.label)
        case .averageSpeed:
            return (formatSpeed(workout.averageSpeed, false), currentUnits.speed.label)
        case .heartRate:
            return (workout.heartRate > 0 ? "\(Int(workout.heartRate))" : "--", "bpm")
        case .distance:
            return (formatDistance(workout.totalDistance), nil)
        case .movingTime:
            return (formatTime(workout.movingTime), nil)
        case .elapsedTime:
            return (formatTime(workout.elapsedTime), nil)
        case .elevation:
            return (formatElevation(workout.currentElevation), nil)
        case .grade:
            return (String(format: "%.1f%%", workout.currentGrade), nil)
        case .power:
            return (workout.estimatedPower > 0 ? "\(Int(workout.estimatedPower))" : "--", "W")
        case .distanceRemaining:
            return (formatDistance(workout.navigation.distanceRemaining), nil)
        case .calories:
            return ("\(Int(workout.activeCalories))", "cal")
        case .none:
            return ("", nil)
        }
    }

    private var cardinalDirection: String {
        let heading = workout.heading > 0 ? workout.heading
            : (workout.currentLocation?.course ?? 0)
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((heading + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return dirs[max(0, min(index, dirs.count - 1))]
    }

    private func scheduleAutoSwitch() {
        autoSwitchTask?.cancel()
        autoSwitchTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await MainActor.run { showFullRoute = false }
        }
    }
}

private struct FullRouteCanvas: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared
    var routeAheadColor: RouteColor = .white

    var body: some View {
        let _ = unitState.preferences // register dependency for Canvas redraws
        Canvas { context, size in
            // Safe area insets for watch: top/bottom for rounded corners + UI overlays
            let insetTop: CGFloat = 36
            let insetBottom: CGFloat = 20
            let insetSide: CGFloat = 16

            if let processed = workout.navigation.processedRoute {
                // Route ride: show full planned route
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

                let segIdx = workout.navigation.currentSegmentIndex
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

            // Mile markers
            let markers = computeMileMarkers(points: points)
            for marker in markers {
                let pt = project(marker.coordinate, transform: transform)
                // Flag pole
                context.stroke(
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: pt.y))
                        p.addLine(to: CGPoint(x: pt.x, y: pt.y - 10))
                    },
                    with: .color(.orange),
                    style: StrokeStyle(lineWidth: 1.5))
                // Flag
                context.fill(
                    Path { p in
                        p.move(to: CGPoint(x: pt.x, y: pt.y - 10))
                        p.addLine(to: CGPoint(x: pt.x + 7, y: pt.y - 8))
                        p.addLine(to: CGPoint(x: pt.x, y: pt.y - 6))
                        p.closeSubpath()
                    },
                    with: .color(.orange))
                // Label
                let text = Text("\(marker.mile)")
                    .font(.system(size: 7, weight: .bold))
                    .foregroundColor(.white)
                context.draw(context.resolve(text),
                             at: CGPoint(x: pt.x + 4, y: pt.y - 14))
            }

            if let loc = workout.currentLocation {
                let pos = project(loc.coordinate, transform: transform)
                    if workout.navigation.isOffRoute {
                        let candidates = workout.navigation.rejoinCandidates
                        if candidates.isEmpty {
                            let nearIdx = workout.navigation.currentSegmentIndex
                            let nearPt = project(points[min(nearIdx, points.count - 1)].coordinate, transform: transform)
                            var returnLine = Path()
                            returnLine.move(to: pos)
                            returnLine.addLine(to: nearPt)
                            context.stroke(returnLine, with: .color(.red),
                                           style: StrokeStyle(lineWidth: 2, lineCap: .round, dash: [6, 4]))
                        } else {
                            for (i, candidate) in candidates.enumerated() {
                                let candidatePt = project(candidate.coordinate, transform: transform)
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
                let trail = workout.recordedLocations
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

                // Rider dot at current position (last recorded point)
                if let loc = workout.currentLocation {
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

private struct BreadcrumbCanvas: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared
    let viewDistance: Double
    var useCompassHeading: Bool = true
    var routeAheadColor: RouteColor = .white

    private let routeLineWidth: CGFloat = 6

    var body: some View {
        let _ = unitState.preferences // register dependency for Canvas redraws
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            Canvas { context, size in
                guard let location = workout.currentLocation else { return }

                // Free ride: draw rider trail only
                if workout.navigation.processedRoute == nil {
                    let riderScreenX = size.width / 2
                    let riderScreenY = size.height * 0.75
                    let metersPerPx = min(size.width, size.height) / viewDistance

                    let center = location.coordinate
                    let cosLat = cos(center.latitude * .pi / 180)

                    let bearing: Double
                    if useCompassHeading, workout.heading > 0 {
                        bearing = workout.heading
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

                    let trail = workout.recordedLocations
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

                guard let processed = workout.navigation.processedRoute else { return }
                let points = processed.points
                let segIdx = workout.navigation.currentSegmentIndex
                guard points.count >= 2, segIdx < points.count else { return }

                let currentDist = workout.navigation.distanceAlongRoute

                let bearing: Double
                if useCompassHeading, workout.heading > 0 {
                    bearing = workout.heading
                } else if workout.speed > 1.0, location.course >= 0 {
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

                // Feature 2: Draw all visible route sections (distant sections first, dimmer)
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

                    // Skip points already in the primary window
                    if point.distanceFromStart >= minDist - 200 && point.distanceFromStart <= maxDist + 200 {
                        if distantGrayStarted { distantGrayStarted = false }
                        if distantGreenStarted { distantGreenStarted = false }
                        continue
                    }

                    let pt = toScreen(point.coordinate)

                    // Check if point is on screen
                    guard pt.x >= -margin && pt.x <= screenW + margin &&
                          pt.y >= -margin && pt.y <= screenH + margin else {
                        if distantGrayStarted { distantGrayStarted = false }
                        if distantGreenStarted { distantGreenStarted = false }
                        continue
                    }

                    if point.distanceFromStart <= currentDist {
                        // Completed portion — green
                        if distantGrayStarted { distantGrayStarted = false }
                        if !distantGreenStarted {
                            distantGreenPath.move(to: pt)
                            distantGreenStarted = true
                        } else {
                            distantGreenPath.addLine(to: pt)
                        }
                    } else {
                        // Uncompleted portion — gray
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

                // Mile markers on breadcrumb view
                struct MileMarkerCache {
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

                let markers = MileMarkerCache.markers(for: points)
                for marker in markers {
                    let pt = toScreen(marker.coordinate)
                    // Only draw if on screen
                    guard pt.x >= -10 && pt.x <= screenW + 10 &&
                          pt.y >= -10 && pt.y <= screenH + 10 else { continue }
                    // Flag pole
                    context.stroke(
                        Path { p in
                            p.move(to: CGPoint(x: pt.x, y: pt.y))
                            p.addLine(to: CGPoint(x: pt.x, y: pt.y - 12))
                        },
                        with: .color(.orange),
                        style: StrokeStyle(lineWidth: 1.5))
                    // Flag
                    context.fill(
                        Path { p in
                            p.move(to: CGPoint(x: pt.x, y: pt.y - 12))
                            p.addLine(to: CGPoint(x: pt.x + 8, y: pt.y - 9.5))
                            p.addLine(to: CGPoint(x: pt.x, y: pt.y - 7))
                            p.closeSubpath()
                        },
                        with: .color(.orange))
                    // Label
                    let text = Text("\(marker.mile)")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundColor(.white)
                    context.draw(context.resolve(text),
                                 at: CGPoint(x: pt.x + 5, y: pt.y - 16))
                }

                if workout.navigation.isOffRoute {
                    let trail = workout.recordedLocations
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

                // Off-route: dashed red lines to rejoin candidates
                if workout.navigation.isOffRoute {
                    let candidates = workout.navigation.rejoinCandidates
                    if candidates.isEmpty {
                        // Fallback: single line to nearest route point
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
                            let candidateScreen = toScreen(candidate.coordinate)
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

                    // Rider dot — red when off-route
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
    }
}
