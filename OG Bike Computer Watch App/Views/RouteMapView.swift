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

    @State private var zoomIndex: Int = -1 // -1 means "use default from config"
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
                            routeAheadColor: mapConfig.routeAheadColor)
                    } else {
                        RouteMapBreadcrumbCanvas(
                            data: routeMapData,
                            viewDistance: currentViewDistance,
                            useCompassHeading: useCompassHeading,
                            routeAheadColor: mapConfig.routeAheadColor)
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

                VStack(spacing: 2) {
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
                        .frame(width: 48, height: 48)
                        .contentShape(Rectangle())
                        .opacity(toggleButtonOpacity)
                    }

                    if mapConfig.showHeading {
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
    private func routeContent(location: CLLocation) -> some MapContent {
        if let processed = workout.navigation.processedRoute {
            let points = processed.points
            let segIdx = min(workout.navigation.currentSegmentIndex, points.count - 1)

            // Completed portion (green) — all points, no subsampling
            if segIdx > 0 {
                let behindCoords = points[0...segIdx].map(\.coordinate)
                MapPolyline(coordinates: behindCoords)
                    .stroke(.green, lineWidth: 6)
            }

            // Ahead portion: near segment (configured color) + far segment (grey)
            if segIdx < points.count - 1 {
                let currentDist = points[segIdx].distanceFromStart
                let nearThreshold = currentDist + 3219 // ~2 miles ahead

                // Find split point where route exceeds 2 miles ahead
                let farStartIdx = points[(segIdx + 1)...].firstIndex(where: {
                    $0.distanceFromStart > nearThreshold
                }) ?? points.count

                // Near ahead (configured color)
                if farStartIdx > segIdx {
                    let nearCoords = points[segIdx..<farStartIdx].map(\.coordinate)
                    MapPolyline(coordinates: nearCoords)
                        .stroke(routeAheadColor.color, lineWidth: 6)
                }

                // Far ahead (grey, thinner)
                if farStartIdx < points.count {
                    let farCoords = points[(farStartIdx - 1)...].map(\.coordinate)
                    MapPolyline(coordinates: farCoords)
                        .stroke(.gray.opacity(0.5), lineWidth: 3)
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
                    .stroke(.red, lineWidth: 3)
                }
                ForEach(0..<candidates.count, id: \.self) { i in
                    MapPolyline(coordinates: [
                        location.coordinate,
                        candidates[i].coordinate
                    ])
                    .stroke(.red.opacity(i == 0 ? 1.0 : 0.5), lineWidth: i == 0 ? 3 : 2)
                }

                // Recorded trail when off-route (orange)
                let trail = workout.recordedLocations
                if trail.count >= 2 {
                    MapPolyline(coordinates: trail.map(\.coordinate))
                        .stroke(.orange.opacity(0.7), lineWidth: 3)
                }
            }

            // Mile markers — alternate above/below the route line
            let markers = computeMileMarkers(points: points)
            ForEach(Array(markers.enumerated()), id: \.element.mile) { idx, marker in
                let below = idx.isMultiple(of: 2) == false
                Annotation("", coordinate: marker.coordinate, anchor: below ? .top : .bottom) {
                    if below {
                        VStack(spacing: 0) {
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                                .rotationEffect(.degrees(180))
                            Text("\(marker.mile)")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    } else {
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
                    .stroke(.green.opacity(0.6), lineWidth: 4)
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
