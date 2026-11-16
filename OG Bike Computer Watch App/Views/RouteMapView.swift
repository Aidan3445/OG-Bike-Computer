//
//  RouteMapView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI
import CoreLocation
import MapKit

struct RouteMapView: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced

    /// When true, renders a stripped-down version for the metric screen turn overlay
    /// (no buttons, no stats, no heading — just route shape, orientation, and rider position)
    var isOverlay: Bool = false

    @State private var showFullRoute = false
    @State private var autoSwitchTask: Task<Void, Never>?
    @State private var toggleButtonOpacity: Double = 1.0
    @State private var toggleFadeTask: Task<Void, Never>?

    /// Shared with the turn overlay so both maps show the same zoom, and so
    /// the rainbow route (scaled by zoom) looks the same in each. -1 means
    /// "use default from config".
    @Binding var zoomIndex: Int
    private var mapConfig: MapScreenConfig { workout.ridePreferences.mapScreen }

    private var zoomLevels: [Double] { mapConfig.computedZoomLevels }

    private var effectiveZoomIndex: Int {
        if zoomIndex < 0 { return mapConfig.defaultZoomIndex }
        return min(zoomIndex, zoomLevels.count - 1)
    }

    private var currentViewDistance: Double {
        zoomLevels.isEmpty ? 400 : zoomLevels[effectiveZoomIndex]
    }

    private var useCompassHeading: Bool {
        workout.ridePreferences.mapRotation == .headingUp && !isLuminanceReduced
    }

    private var mapDetailEnabled: Bool {
        mapConfig.mapDetail != .off && !isLuminanceReduced
    }

    /// Snapshot of WorkoutManager state used by the shared route-map canvases.
    private var routeMapData: RouteMapData {
        RouteMapData(
            currentLocation: workout.currentLocation,
            processedRoute: workout.navigation.processedRoute,
            currentSegmentIndex: workout.navigation.currentSegmentIndex,
            distanceAlongRoute: workout.navigation.distanceAlongRoute,
            heading: workout.heading,
            speed: workout.speed,
            recordedLocations: workout.recordedLocations,
            isOffRoute: workout.navigation.isOffRoute,
            rejoinCandidateCoords: workout.navigation.rejoinCandidates.map(\.coordinate),
            showWaypointsOnRouteMap: workout.ridePreferences.mapScreen.waypointDisplay.showsOnRouteMap)
    }

    var body: some View {
        ZStack {
            Group {
                if showFullRoute || !workout.hasRoute {
                    // Full route view: Map background + Canvas overlay (aligned, no rotation)
                    if mapDetailEnabled {
                        ZStack {
                            fullRouteMapBackground
                            RouteMapFullRouteCanvas(data: routeMapData, routeAheadColor: mapConfig.routeAheadColor)
                        }
                    } else {
                        RouteMapFullRouteCanvas(data: routeMapData, routeAheadColor: mapConfig.routeAheadColor)
                    }
                } else {
                    // Breadcrumb view: use MapKit-native rendering when map is on
                    if mapDetailEnabled {
                        BreadcrumbMapView(
                            workout: workout,
                            viewDistance: currentViewDistance,
                            useCompassHeading: useCompassHeading,
                            routeAheadColor: mapConfig.routeAheadColor,
                            defaultZoom: mapConfig.effectiveDefaultZoom)
                    } else {
                        RouteMapBreadcrumbCanvas(
                            data: routeMapData,
                            viewDistance: currentViewDistance,
                            useCompassHeading: useCompassHeading,
                            routeAheadColor: mapConfig.routeAheadColor,
                            defaultZoom: mapConfig.effectiveDefaultZoom)
                    }
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

    // MARK: - Full Route Map Background

    @ViewBuilder
    private var fullRouteMapBackground: some View {
        if let processed = workout.navigation.processedRoute {
            let center = CLLocationCoordinate2D(
                latitude: (processed.minLat + processed.maxLat) / 2,
                longitude: (processed.minLon + processed.maxLon) / 2)
            let span = MKCoordinateSpan(
                latitudeDelta: (processed.maxLat - processed.minLat) * 1.3,
                longitudeDelta: (processed.maxLon - processed.minLon) * 1.3)
            Map(position: .constant(.region(MKCoordinateRegion(center: center, span: span))),
                interactionModes: []) {}
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
        } else {
            let trail = workout.recordedLocations
            if trail.count >= 2 {
                let lats = trail.map(\.coordinate.latitude)
                let lons = trail.map(\.coordinate.longitude)
                let center = CLLocationCoordinate2D(
                    latitude: (lats.min()! + lats.max()!) / 2,
                    longitude: (lons.min()! + lons.max()!) / 2)
                let span = MKCoordinateSpan(
                    latitudeDelta: (lats.max()! - lats.min()!) * 1.3,
                    longitudeDelta: (lons.max()! - lons.min()!) * 1.3)
                Map(position: .constant(.region(MKCoordinateRegion(center: center, span: span))),
                    interactionModes: []) {}
                .mapStyle(.standard(pointsOfInterest: .excludingAll))
                .mapControlVisibility(.hidden)
                .allowsHitTesting(false)
            }
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

                VStack(alignment: .trailing, spacing: -3) {
                    HStack(spacing: -10) {
                        if mapConfig.showHeading {
                            // Mount the cardinal inside the same 40 × 40
                            // outer slot the buttons use, with the text
                            // centered in a 36-pt circle area (matching the
                            // buttons' visible circle). This way the cardinal
                            // aligns identically whether the toggle is on or
                            // off, and stays in column with the waveform
                            // button below.
                            Text(cardinalDirection)
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(width: 36, height: 36)
                                .frame(width: 40, height: 40)
                        }

                        if workout.hasRoute && mapConfig.showFullRouteToggle {
                            Button {
                                showFullRoute.toggle()
                                if showFullRoute {
                                    scheduleAutoSwitch()
                                    scheduleToggleFade()
                                } else {
                                    autoSwitchTask?.cancel()
                                    toggleFadeTask?.cancel()
                                    withAnimation(.easeIn(duration: 0.15)) { toggleButtonOpacity = 1.0 }
                                }
                            } label: {
                                Image(systemName: showFullRoute ? "scope" : "map")
                                    .font(.system(size: 16, weight: .bold))
                                    .frame(width: 36, height: 36)
                                    .background(.ultraThinMaterial)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                            .frame(width: 40, height: 40)
                            .contentShape(Rectangle())
                            .opacity(toggleButtonOpacity)
                        }
                    }

                    // Repeat the upcoming turn alert. Tucked into the top-right
                    // stack so it stays clear of the rider dot (which the map
                    // offsets toward bottom-center). Same 40×40 tap-target as
                    // the toggle so the two buttons align vertically.
                    if mapConfig.showRepeatAlertButton,
                       !showFullRoute,
                       !workout.navigation.isOffRoute,
                       workout.navigation.nextTurn != nil {
                        Button {
                            VoiceNavigator.shared.repeatUpcomingTurnAlert()
                        } label: {
                            Image(systemName: "waveform")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .frame(width: 40, height: 40)
                        .contentShape(Rectangle())
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
        let offRoute = workout.navigation.isOffRoute
        if offRoute || workout.navigation.nextTurn != nil || !workout.hasRoute || mapConfig.primaryStat != .none || !mapConfig.secondaryStats.filter({ $0 != .none }).isEmpty {
            VStack(spacing: 1) {
                if offRoute {
                    Text("OFF ROUTE")
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(.red)
                    Text(formatTurnDistance(workout.navigation.nearestRouteDistance))
                        .font(.system(size: 11, weight: .semibold, design: .rounded))
                        .monospacedDigit()
                        .foregroundStyle(.red.opacity(0.85))
                    Divider().frame(maxWidth: 60).padding(.vertical, 1)
                }
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

                // Turn info (hidden when off-route — the OFF ROUTE banner above
                // covers the same row, and the upcoming turn is moot until the
                // rider rejoins the route)
                if mapConfig.showTurnInfo, !offRoute, let turn = workout.navigation.nextTurn {
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
            .background(offRoute ? AnyShapeStyle(.red.opacity(0.18)) : AnyShapeStyle(.black.opacity(0.6)))
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

    private func scheduleToggleFade() {
        toggleFadeTask?.cancel()
        toggleFadeTask = Task {
            // Brief delay so the button is visible for the tap feedback
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeOut(duration: 0.35)) { toggleButtonOpacity = 0 }
            }
            try? await Task.sleep(for: .seconds(2.5))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                withAnimation(.easeIn(duration: 0.35)) { toggleButtonOpacity = 1.0 }
            }
        }
    }
}

// MARK: - Breadcrumb Map View (MapKit-native route rendering)

private struct BreadcrumbMapView: View {
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared
    let viewDistance: Double
    var useCompassHeading: Bool = true
    var routeAheadColor: RouteColor = .white
    /// Sets the rainbow's cycle length. See `RouteRainbow.routeWavelength`.
    var defaultZoom: Double = 400

    private var bearing: Double {
        guard let location = workout.currentLocation else { return 0 }
        if useCompassHeading, workout.heading > 0 { return workout.heading }
        if workout.speed > 1.0, location.course >= 0 { return location.course }
        if let processed = workout.navigation.processedRoute {
            let segIdx = workout.navigation.currentSegmentIndex
            if segIdx < processed.points.count {
                return processed.points[segIdx].bearingToNext
            }
        }
        return location.course >= 0 ? location.course : 0
    }

    var body: some View {
        let _ = unitState.preferences
        if let location = workout.currentLocation {
            // Offset center forward along bearing to push rider toward bottom of screen
            let offsetCenter = location.coordinate.offset(
                distanceMeters: viewDistance * 0.3, bearingDegrees: bearing)

            Map(position: .constant(.camera(MapCamera(
                centerCoordinate: offsetCenter,
                distance: viewDistance * 2.0,
                heading: useCompassHeading ? bearing : 0,
                pitch: 0
            ))),
                interactionModes: []
            ) {
                routeContent(location: location)
            }
            .mapStyle(.standard(pointsOfInterest: .excludingAll))
            .mapControlVisibility(.hidden)
            .allowsHitTesting(false)
        }
    }

    @MapContentBuilder
    private func rainbowPolylines(_ segments: [RouteRainbow.MapSegment], lineWidth: CGFloat) -> some MapContent {
        ForEach(segments, id: \.id) { segment in
            MapPolyline(coordinates: segment.coordinates)
                .stroke(segment.color, style: .roundedLine(lineWidth))
        }
    }

    @MapContentBuilder
    private func routeContent(location: CLLocation) -> some MapContent {
        if let processed = workout.navigation.processedRoute {
            let points = processed.points
            let segIdx = min(workout.navigation.currentSegmentIndex, points.count - 1)
            let rainbow = routeAheadColor == .rainbow

            // Thin route underneath everything, so there's never a gap where the
            // thick stretch ends. Solid colors draw the whole route once; the
            // rainbow takes many pieces, so it only covers the route near the rider.
            if rainbow {
                rainbowPolylines(RouteLineMapCache.rainbowFar(for: processed, segmentIndex: segIdx,
                                                              viewDistance: viewDistance, defaultZoom: defaultZoom),
                                 lineWidth: RouteLineLayout.farLineWidth)
            } else {
                MapPolyline(coordinates: RouteLineMapCache.coordinates(for: processed))
                    .stroke(routeAheadColor.color.opacity(RouteLineLayout.farOpacity),
                            style: .roundedLine(RouteLineLayout.farLineWidth))
            }

            // Completed portion, all points, covering the thin line under it
            if segIdx > 0 {
                let behindCoords = points[0...segIdx].map(\.coordinate)
                MapPolyline(coordinates: behindCoords)
                    .stroke(Color.riddenRoute, style: .roundedLine(RouteLineLayout.nearLineWidth))
            }

            // Thick stretch just ahead of the rider
            if segIdx < points.count - 1 {
                if rainbow {
                    rainbowPolylines(
                        RouteLineMapCache.rainbowNear(for: processed, segmentIndex: segIdx,
                                                      viewDistance: viewDistance, defaultZoom: defaultZoom),
                        lineWidth: RouteLineLayout.nearLineWidth)
                } else {
                    let nearEnd = points[segIdx].distanceFromStart + RouteLineLayout.nearAhead(viewDistance)
                    let endIdx = points[(segIdx + 1)...].firstIndex { $0.distanceFromStart > nearEnd } ?? points.count - 1
                    MapPolyline(coordinates: points[segIdx...endIdx].map(\.coordinate))
                        .stroke(routeAheadColor.color, style: .roundedLine(RouteLineLayout.nearLineWidth))
                }
            }

            // Off-route indicators
            if workout.navigation.isOffRoute {
                // Rejoin candidate lines
                let candidates = workout.navigation.rejoinCandidates
                if candidates.isEmpty {
                    MapPolyline(coordinates: [
                        location.coordinate,
                        points[min(segIdx, points.count - 1)].coordinate
                    ])
                    .stroke(.red, style: .roundedLine(3))
                }
                ForEach(0..<candidates.count, id: \.self) { i in
                    MapPolyline(coordinates: [
                        location.coordinate,
                        candidates[i].coordinate
                    ])
                    .stroke(.red.opacity(i == 0 ? 1.0 : 0.5), style: .roundedLine(i == 0 ? 3 : 2))
                }

                // Recorded trail when off-route (orange)
                let trail = workout.recordedLocations
                if trail.count >= 2 {
                    MapPolyline(coordinates: trail.map(\.coordinate))
                        .stroke(.orange.opacity(0.7), style: .roundedLine(3))
                }
            }

            // Mile markers — always above the route line
            let markers = computeMileMarkers(points: points)
            ForEach(markers, id: \.mile) { marker in
                Annotation("", coordinate: marker.coordinate, anchor: .bottom) {
                    VStack(spacing: 0) {
                        Text("\(marker.mile)")
                            .font(.system(size: 8, weight: .bold))
                            .foregroundStyle(.white)
                        Image(systemName: "flag.fill")
                            .font(.system(size: 8))
                            .foregroundStyle(.orange)
                    }
                }
            }

            // POI pins (MapKit-native breadcrumb view)
            if workout.ridePreferences.mapScreen.waypointDisplay.showsOnRouteMap {
                ForEach(0..<processed.pois.count, id: \.self) { i in
                    Annotation("", coordinate: processed.pois[i].coordinate, anchor: .bottom) {
                        Image(systemName: "mappin")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.orange)
                    }
                }
            }
        } else {
            // Free ride: full recorded trail
            let trail = workout.recordedLocations
            if trail.count >= 2 {
                MapPolyline(coordinates: trail.map(\.coordinate))
                    .stroke(.green.opacity(0.6), style: .roundedLine(4))
            }
        }

        // Rider dot
        Annotation("", coordinate: location.coordinate, anchor: .center) {
            ZStack {
                Circle()
                    .fill(workout.navigation.isOffRoute ? .red.opacity(0.3) : .white)
                    .frame(width: 16, height: 16)
                Circle()
                    .fill(workout.navigation.isOffRoute ? .red : .blue)
                    .frame(width: 12, height: 12)
            }
        }
    }
}

// MARK: - Coordinate Offset Helper

private extension CLLocationCoordinate2D {
    /// Returns a new coordinate offset by the given distance (meters) along a bearing (degrees).
    func offset(distanceMeters: Double, bearingDegrees: Double) -> CLLocationCoordinate2D {
        let R = 6_371_000.0 // Earth radius in meters
        let d = distanceMeters / R
        let brng = bearingDegrees * .pi / 180
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180

        let lat2 = asin(sin(lat1) * cos(d) + cos(lat1) * sin(d) * cos(brng))
        let lon2 = lon1 + atan2(sin(brng) * sin(d) * cos(lat1), cos(d) - sin(lat1) * sin(lat2))

        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi)
    }
}

// MARK: - Route line cache

/// Route-line geometry for the MapKit breadcrumb, kept between renders. The
/// map re-renders on every heading and location update, but these only change
/// with the route, the zoom, or the rider's segment.
private enum RouteLineMapCache {
    private static var coordinatesKey: [Double] = []
    private static var cachedCoordinates: [CLLocationCoordinate2D] = []
    private static var farKey: [Double] = []
    private static var cachedFar: [RouteRainbow.MapSegment] = []
    private static var nearKey: [Double] = []
    private static var cachedNear: [RouteRainbow.MapSegment] = []

    /// Hue steps per rainbow cycle. Small enough steps read as a smooth fade;
    /// the thin line is dimmer, so it gets away with fewer pieces.
    private static let nearStepsPerCycle = 64
    private static let farStepsPerCycle = 32

    private static func key(_ route: ProcessedRoute, _ extra: Double...) -> [Double] {
        [Double(route.points.count), route.points.last?.distanceFromStart ?? 0] + extra
    }

    static func coordinates(for route: ProcessedRoute) -> [CLLocationCoordinate2D] {
        let k = key(route)
        if k != coordinatesKey {
            cachedCoordinates = route.points.map(\.coordinate)
            coordinatesKey = k
        }
        return cachedCoordinates
    }

    static func rainbowNear(for route: ProcessedRoute, segmentIndex: Int, viewDistance: Double,
                            defaultZoom: Double) -> [RouteRainbow.MapSegment] {
        let k = key(route, viewDistance, defaultZoom, Double(segmentIndex))
        if k != nearKey {
            let points = route.points
            let start = points[segmentIndex].distanceFromStart
            let end = min(start + RouteLineLayout.nearAhead(viewDistance), points.last?.distanceFromStart ?? 0)
            let step = RouteRainbow.routeWavelength(defaultZoom: defaultZoom) / Double(nearStepsPerCycle)
            cachedNear = end > start
                ? RouteRainbow.mapSegments(
                    along: points, steps: Array(Int(start / step)...Int(end / step)), clampedTo: start...end,
                    defaultZoom: defaultZoom, stepsPerCycle: nearStepsPerCycle, dimmed: false)
                : []
            nearKey = k
        }
        return cachedNear
    }

    /// Thin rainbow past the thick stretch, for every piece of route that
    /// passes within a couple of screens of the rider. That includes switchbacks
    /// and loops that come back near you much later in the route.
    static func rainbowFar(for route: ProcessedRoute, segmentIndex: Int, viewDistance: Double,
                           defaultZoom: Double) -> [RouteRainbow.MapSegment] {
        let k = key(route, viewDistance, defaultZoom, Double(segmentIndex))
        if k != farKey {
            let points = route.points
            let routeEnd = points.last?.distanceFromStart ?? 0
            let nearEnd = min(points[segmentIndex].distanceFromStart + RouteLineLayout.nearAhead(viewDistance), routeEnd)
            let step = RouteRainbow.routeWavelength(defaultZoom: defaultZoom) / Double(farStepsPerCycle)
            let radius = viewDistance * 2

            // Flat meters around the rider's segment, plenty accurate at this scale.
            let center = points[segmentIndex].coordinate
            let cosLat = cos(center.latitude * .pi / 180)
            func local(_ c: CLLocationCoordinate2D) -> (x: Double, y: Double) {
                ((c.longitude - center.longitude) * cosLat * 111_320, (c.latitude - center.latitude) * 111_320)
            }

            var steps = Set<Int>()
            if nearEnd < routeEnd {
                var prev = local(points[RouteRainbow.index(atOrBefore: nearEnd, in: points)].coordinate)
                for j in RouteRainbow.index(atOrBefore: nearEnd, in: points)..<(points.count - 1) {
                    let next = local(points[j + 1].coordinate)
                    // Distance from the rider to this segment, so long straight
                    // segments crossing the screen still count.
                    let dx = next.x - prev.x, dy = next.y - prev.y
                    let lengthSq = dx * dx + dy * dy
                    let t = lengthSq > 0 ? min(max(-(prev.x * dx + prev.y * dy) / lengthSq, 0), 1) : 0
                    let px = prev.x + dx * t, py = prev.y + dy * t
                    if px * px + py * py <= radius * radius {
                        let lo = Int(max(points[j].distanceFromStart, nearEnd) / step)
                        let hi = Int(points[j + 1].distanceFromStart / step)
                        if hi >= lo { steps.formUnion(lo...hi) }
                    }
                    prev = next
                }
            }
            cachedFar = RouteRainbow.mapSegments(
                along: points, steps: steps.sorted(), clampedTo: nearEnd...max(routeEnd, nearEnd),
                defaultZoom: defaultZoom, stepsPerCycle: farStepsPerCycle, dimmed: true)
            farKey = k
        }
        return cachedFar
    }
}
