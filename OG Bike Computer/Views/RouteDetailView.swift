//
//  RouteDetailView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Charts

struct RouteDetailView: View {
    let route: Route
    let isOnWatch: Bool
    let isUploading: Bool
    let isQueued: Bool
    let isUploadBlocked: Bool
    let canSendToWatch: Bool
    let onSend: () -> Void
    /// Optional — when provided, enables the Cue Editor. (Callers that don't
    /// need editing can pass nil.)
    var routeStore: RouteStore? = nil
    @ObservedObject private var unitState = UnitState.shared

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showOverwriteAlert = false

    // Cached derived data — computed once on appear to avoid O(n) work on every body recompute
    @State private var cachedCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedMileMarkers: [MileMarker] = []
    @State private var cachedElevationExtremes: (high: TrackPoint, low: TrackPoint)? = nil
    @State private var cachedElevationData: [ProcessedPoint] = []
    @State private var panelPage = 0
    @State private var scrubDistance: Double? = nil
    @State private var scrubCoordinate: CLLocationCoordinate2D? = nil

    // Cue Editor state
    @State private var isEditingCues: Bool = false
    @StateObject private var cueEditorHolder = CueEditorHolder()
    /// Live map heading, updated from `onMapCameraChange`. Used to counter-rotate
    /// the highlight chevrons so they stay aligned with the actual route, not
    /// with the screen, when the camera turns.
    @State private var currentMapHeading: Double = 0

    var body: some View {
        let _ = unitState.preferences
        GeometryReader { proxy in
        ZStack(alignment: .bottom) {
            MapReader { mapProxy in
            Map(position: $mapPosition) {
                // Route polyline
                MapPolyline(coordinates: cachedCoordinates)
                    .stroke(.blue, lineWidth: 4)

                // Start marker
                if let first = cachedCoordinates.first {
                    Annotation("Start", coordinate: first) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                // End marker
                if let last = cachedCoordinates.last {
                    Annotation("End", coordinate: last) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                // Cue Editor turn annotations (only while editing).
                // CueEditorTurnPin owns its own observation of the editor, so
                // the icon/color updates live — MapKit's annotation diffing
                // doesn't always re-evaluate the content closure on its own.
                if isEditingCues, let editor = cueEditorHolder.viewModel {
                    // Highlight overlay for the selected turn: a thick white
                    // semi-transparent line on top of the route, with chevrons
                    // at the endpoints showing direction of travel.
                    if let selID = editor.selection,
                       let selEntry = editor.allEntries.first(where: { $0.id == selID }) {
                        let highlight = editor.highlightCoordinates(for: selEntry)
                        if highlight.count >= 2 {
                            MapPolyline(coordinates: highlight)
                                .stroke(.white.opacity(0.55), lineWidth: 9)

                            // Travel-direction chevrons at start and end. World
                            // bearings come from the actual polyline segments
                            // (first→second, second-to-last→last) so the
                            // arrows visually align with the highlight even
                            // through bendy approaches; counter-rotated by the
                            // live map heading so they don't follow the camera.
                            let startBearing = RouteProcessor.bearing(
                                from: highlight[0],
                                to: highlight[1]
                            )
                            let endBearing = RouteProcessor.bearing(
                                from: highlight[highlight.count - 2],
                                to: highlight[highlight.count - 1]
                            )
                            Annotation("", coordinate: highlight[0]) {
                                HighlightChevron(rotation: startBearing - currentMapHeading)
                            }
                            Annotation("", coordinate: highlight[highlight.count - 1]) {
                                HighlightChevron(rotation: endBearing - currentMapHeading)
                            }
                        }
                    }

                    // Draw unselected pins first; the selected pin goes last
                    // so it sits on top of overlapping neighbors at the same
                    // spot (loops, double-backs).
                    ForEach(editor.allEntries.filter { $0.id != editor.selection }) { entry in
                        Annotation("", coordinate: entry.turn.coordinate) {
                            CueEditorTurnPin(editor: editor, entry: entry)
                                .onTapGesture {
                                    editor.select(entry.id)
                                }
                        }
                    }
                    if let selID = editor.selection,
                       let selEntry = editor.allEntries.first(where: { $0.id == selID }) {
                        Annotation("", coordinate: selEntry.turn.coordinate) {
                            CueEditorTurnPin(editor: editor, entry: selEntry)
                                .onTapGesture {
                                    editor.select(nil)
                                }
                        }
                    }

                    // Editor-mode waypoint pins (imported + user-added).
                    ForEach(editor.waypointEntries) { wp in
                        Annotation("", coordinate: wp.coordinate) {
                            CueEditorWaypointPin(
                                isSelected: editor.waypointSelection == wp.id,
                                isUserAdded: {
                                    if case .userAdded = wp.source { return true }
                                    return false
                                }()
                            )
                            .onTapGesture {
                                if editor.placementMode == .none {
                                    if editor.waypointSelection == wp.id {
                                        editor.selectWaypoint(nil)
                                    } else {
                                        editor.selectWaypoint(wp.id)
                                    }
                                }
                            }
                        }
                    }
                }

                // Elevation markers
                if let peaks = cachedElevationExtremes {
                    if let highElev = peaks.high.elevation {
                        Annotation("", coordinate: peaks.high.coordinate) {
                            VStack(spacing: 2) {
                                Text(formatElevation(highElev))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.orange)
                                    .clipShape(Capsule())
                                    .opacity(0.5)
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.orange)
                                    .opacity(0.5)
                            }
                        }
                    }

                    if let lowElev = peaks.low.elevation {
                        Annotation("", coordinate: peaks.low.coordinate) {
                            VStack(spacing: 2) {
                                Image(systemName: "triangle.fill")
                                    .font(.system(size: 10))
                                    .foregroundStyle(.cyan)
                                    .rotationEffect(.degrees(180))
                                    .opacity(0.5)
                                Text(formatElevation(lowElev))
                                    .font(.caption2.weight(.bold))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.cyan)
                                    .clipShape(Capsule())
                                    .opacity(0.5)
                            }
                        }
                    }
                }

                // Mile markers
                ForEach(Array(cachedMileMarkers.enumerated()), id: \.offset) { _, marker in
                    Annotation("", coordinate: marker.coordinate) {
                        Text("\(marker.mile) \(currentUnits.distance.label)")
                            .font(.system(size: 10, weight: .bold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 4)
                            .padding(.vertical, 1)
                            .background(Color.accentColor)
                            .clipShape(Capsule())
                    }
                }

                // Waypoints / POIs
                ForEach(Array((route.waypoints?.pois ?? []).enumerated()), id: \.offset) { _, poi in
                    Annotation(poi.name, coordinate: poi.coordinate) {
                        WaypointPin()
                    }
                }

                // Scrub position indicator
                if let coord = scrubCoordinate {
                    Annotation("", coordinate: coord) {
                        Circle()
                            .fill(.white)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(Color.green, lineWidth: 3))
                            .shadow(radius: 3)
                    }
                }

                // Current location
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }
            .onMapCameraChange(frequency: .continuous) { context in
                currentMapHeading = context.camera.heading
            }
            // Forward map taps to the editor view-model while a placement
            // mode is active. SpatialTapGesture exposes the local point so we
            // can ask MapKit to convert it into a real-world coordinate.
            .gesture(
                SpatialTapGesture().onEnded { event in
                    guard isEditingCues, let editor = cueEditorHolder.viewModel else { return }
                    guard editor.placementMode != .none else { return }
                    if let coord = mapProxy.convert(event.location, from: .local) {
                        editor.handleMapTap(at: coord)
                    }
                }
            )
            }  // end: MapReader

            // Editor panel takes over while in cue-editor mode
            if isEditingCues, let editor = cueEditorHolder.viewModel {
                VStack(spacing: 0) {
                    Spacer()
                    CueEditorPanel(viewModel: editor, availableHeight: proxy.size.height)
                }
            } else {
            // Stats overlay — collapsed (button) ↔ compact (stats)
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 6) {
                    if panelState != .collapsed {
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 36, height: 4)
                            .frame(maxWidth: .infinity)
                            .frame(height: 30)
                            .contentShape(Rectangle())
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    panelState = .collapsed
                                }
                            }
                            .gesture(
                                DragGesture(minimumDistance: 10)
                                    .onEnded { value in
                                        guard abs(value.translation.height) > 10 else { return }
                                        let skipsCompact = (panelPage == 1)
                                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                            if value.translation.height > 0 {
                                                switch panelState {
                                                case .expanded: panelState = skipsCompact ? .collapsed : .compact
                                                case .compact: panelState = .collapsed
                                                case .collapsed: break
                                                }
                                            } else {
                                                switch panelState {
                                                case .collapsed: panelState = skipsCompact ? .expanded : .compact
                                                case .compact: panelState = .expanded
                                                case .expanded: break
                                                }
                                            }
                                        }
                                    }
                            )

                        TabView(selection: $panelPage) {
                            // Page 0: Stats
                            VStack {
                                LazyVGrid(columns: [
                                    GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                                ], spacing: 10) {
                                    StatItem(label: "Distance", value: formatDistance(route.distance))
                                    if route.elevationGain > 0 {
                                        StatItem(label: "Elev Gain", value: formatElevation(route.elevationGain))
                                    }
                                    if route.elevationLoss > 0 {
                                        StatItem(label: "Elev Loss", value: formatElevation(route.elevationLoss))
                                    }
                                }
                                Spacer(minLength: 0)
                            }
                            .tag(0)

                            // Page 1: Elevation Chart
                            if !cachedElevationData.isEmpty {
                                VStack {
                                    RouteElevationChartView(points: cachedElevationData, scrubDistance: $scrubDistance)
                                        .onChange(of: scrubDistance) { _, dist in
                                            scrubCoordinate = dist.map { interpolateRouteCoordinate(at: $0) } ?? nil
                                        }
                                    Spacer(minLength: 0)
                                }
                                .tag(1)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: panelState == .expanded ? 170 : (route.elevationGain > 0 ? 70 : 60))
                        // Lock paging while scrub is active so the chart drag doesn't
                        // bleed into a horizontal page swap.
                        .scrollDisabled(scrubDistance != nil)
                        .onChange(of: panelPage) { _, newPage in
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                panelState = newPage == 1 ? .expanded : .compact
                            }
                        }

                        // Page dots (only if chart data exists)
                        if !cachedElevationData.isEmpty {
                            HStack(spacing: 6) {
                                ForEach(0..<2, id: \.self) { i in
                                    Circle()
                                        .fill(panelPage == i ? Color.primary : Color.secondary.opacity(0.4))
                                        .frame(width: 6, height: 6)
                                }
                            }
                        }
                    } else {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, panelState != .collapsed ? 16 : 0)
                .padding(.bottom, panelState != .collapsed ? 8 : 8)
                .frame(
                    maxWidth: panelState != .collapsed ? .infinity : nil,
                    alignment: panelState != .collapsed ? .center : .trailing
                )
                .frame(width: panelState != .collapsed ? nil : 48, height: panelState != .collapsed ? nil : 48)
                .background(
                    RoundedRectangle(cornerRadius: panelState != .collapsed ? 16 : 24)
                        .fill(.ultraThinMaterial)
                        .shadow(radius: 12, y: 4)
                )
                .padding(.horizontal, panelState != .collapsed ? 12 : 0)
                .padding(.bottom, panelState != .collapsed ? 12 : 24)
                .padding(.trailing, panelState != .collapsed ? 0 : 16)
                .frame(maxWidth: .infinity, alignment: panelState != .collapsed ? .center : .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    if panelState == .collapsed {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            panelState = panelPage == 1 ? .expanded : .compact
                        }
                    }
                }
            }
            }  // end: stats-panel else
        }
        }  // end: GeometryReader
        .navigationTitle(isEditingCues ? "Cue Editor" : route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if isEditingCues {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") {
                        withAnimation { isEditingCues = false }
                    }
                    .font(.body.weight(.semibold))
                }
            } else {
                if let store = routeStore {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            _ = cueEditorHolder.ensure(for: liveRoute(store: store), routeStore: store)
                            withAnimation { isEditingCues = true }
                        } label: {
                            Image(systemName: "pencil.and.list.clipboard")
                                .font(.title3)
                        }
                    }
                }
                if canSendToWatch {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            if isUploading || isQueued || isUploadBlocked { return }
                            if isOnWatch {
                                showOverwriteAlert = true
                            } else {
                                onSend()
                            }
                        } label: {
                            Group {
                                if isUploading {
                                    ProgressView()
                                } else if isQueued {
                                    Image(systemName: "clock.arrow.circlepath")
                                } else {
                                    Image(systemName: isOnWatch ? "checkmark.circle.fill" : "arrow.up.circle")
                                }
                            }
                            .font(.title2)
                            .foregroundStyle(buttonColor(
                                isUploading: isUploading,
                                isQueued: isQueued,
                                isUploadBlocked: isUploadBlocked,
                                isOnWatch: isOnWatch
                            ))
                        }
                        .disabled(isUploadBlocked || isQueued)
                    }
                }
            }
        }
        .alert("Route Already on Watch", isPresented: $showOverwriteAlert) {
            Button("Replace", role: .destructive) {
                onSend()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(route.name)\" is already on your watch. Sending will replace the existing version.")
        }
        .onAppear { buildRouteCache() }
        .onChange(of: cueEditorHolder.viewModel?.selection) { _, newSelection in
            zoomMapToSelection(newSelection)
        }
        .onChange(of: cueEditorHolder.viewModel?.waypointSelection) { _, newID in
            zoomMapToWaypoint(newID)
        }
        .onChange(of: isEditingCues) { _, editing in
            if !editing { cueEditorHolder.teardown() }
        }
    }

    /// Pan/zoom the map to a selected waypoint. Mirrors the cue zoom's
    /// offset so the pin sits about a third of the way down from the top of
    /// the visible map — above the editor panel. Preserves the current map
    /// heading since waypoints have no inherent travel direction.
    private func zoomMapToWaypoint(_ id: UUID?) {
        guard let editor = cueEditorHolder.viewModel,
              let id = id,
              let wp = editor.waypointEntries.first(where: { $0.id == id }) else {
            return
        }
        let heading = currentMapHeading
        // Same constants as the cue path so both feel identical.
        let centerOffsetMeters: Double = 70
        let target = shiftedCoordinate(
            from: wp.coordinate,
            distanceMeters: centerOffsetMeters,
            bearingDegrees: heading + 180
        )
        let camera = MapCamera(
            centerCoordinate: target,
            distance: 700,
            heading: heading,
            pitch: 0
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .camera(camera)
        }
    }

    /// Look up the latest persisted version of this route — the navigation
    /// destination's `route` value is captured at push-time and won't reflect
    /// edits made after entering the screen.
    private func liveRoute(store: RouteStore) -> Route {
        store.routes.first(where: { $0.id == route.id }) ?? route
    }

    /// Pan/zoom the map to focus on the selected turn, oriented so the rider's
    /// approach heading points "up", and biased so the turn sits about a third
    /// of the way down from the top of the visible map — i.e., above the
    /// editor panel no matter how tall the user has dragged it.
    private func zoomMapToSelection(_ sel: CueEntryID?) {
        guard let editor = cueEditorHolder.viewModel,
              let id = sel,
              let entry = editor.allEntries.first(where: { $0.id == id }) else {
            return
        }
        let heading = editor.inboundBearing(for: entry)
        // Move the camera target backward along the heading so the turn appears
        // above the camera-center on screen. ~70m at this zoom keeps the pin
        // comfortably above the panel without crowding the top edge.
        let centerOffsetMeters: Double = 70
        let target = shiftedCoordinate(
            from: entry.turn.coordinate,
            distanceMeters: centerOffsetMeters,
            bearingDegrees: heading + 180
        )
        let camera = MapCamera(
            centerCoordinate: target,
            distance: 700,             // ≈ a 250m radius framing
            heading: heading,
            pitch: 0
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .camera(camera)
        }
    }

    /// Great-circle shift of a coordinate by a given distance along a bearing.
    private func shiftedCoordinate(
        from coord: CLLocationCoordinate2D,
        distanceMeters: Double,
        bearingDegrees: Double
    ) -> CLLocationCoordinate2D {
        let R = 6_371_000.0
        let bearing = bearingDegrees * .pi / 180
        let lat1 = coord.latitude * .pi / 180
        let lon1 = coord.longitude * .pi / 180
        let angular = distanceMeters / R
        let lat2 = asin(sin(lat1) * cos(angular) + cos(lat1) * sin(angular) * cos(bearing))
        let lon2 = lon1 + atan2(
            sin(bearing) * sin(angular) * cos(lat1),
            cos(angular) - sin(lat1) * sin(lat2)
        )
        return CLLocationCoordinate2D(
            latitude: lat2 * 180 / .pi,
            longitude: lon2 * 180 / .pi
        )
    }

    private let minElevDiff: Double = 50 // meters — minimum difference to show markers

    private func buildRouteCache() {
        cachedCoordinates = route.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }

        let pts = route.points
        if pts.count >= 2 {
            var cumDist: Double = 0
            var processed: [ProcessedPoint] = []
            for i in 0..<pts.count {
                if i > 0 {
                    let prev = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
                    let cur  = CLLocation(latitude: pts[i].lat,     longitude: pts[i].lon)
                    cumDist += cur.distance(from: prev)
                }
                processed.append(ProcessedPoint(
                    coordinate: CLLocationCoordinate2D(latitude: pts[i].lat, longitude: pts[i].lon),
                    elevation: pts[i].elevation,
                    distanceFromStart: cumDist,
                    bearingToNext: 0))
            }
            cachedMileMarkers = computeMileMarkers(points: processed)
        }

        let withElev = pts.filter { $0.elevation != nil }
        if let highest = withElev.max(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
           let lowest  = withElev.min(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
           let highElev = highest.elevation,
           let lowElev  = lowest.elevation,
           highElev - lowElev >= minElevDiff {
            cachedElevationExtremes = (highest, lowest)
        }

        // Build chart data
        cachedElevationData = buildRouteElevationData(from: route)
    }

    private func interpolateRouteCoordinate(at targetDist: Double) -> CLLocationCoordinate2D? {
        guard cachedCoordinates.count >= 2 else { return nil }
        let pts = route.points
        var cumDist: Double = 0
        for i in 1..<pts.count {
            let prev = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
            let cur  = CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
            let seg  = cur.distance(from: prev)
            if cumDist + seg >= targetDist {
                let fraction = seg > 0 ? (targetDist - cumDist) / seg : 0
                let lat = pts[i - 1].lat + fraction * (pts[i].lat - pts[i - 1].lat)
                let lon = pts[i - 1].lon + fraction * (pts[i].lon - pts[i - 1].lon)
                return CLLocationCoordinate2D(latitude: lat, longitude: lon)
            }
            cumDist += seg
        }
        return cachedCoordinates.last
    }
}

private struct StatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

