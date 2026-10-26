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
    /// Breadcrumb of the in-progress recording, drawn semi-transparent above
    /// the route polyline so the rider can compare where they've been against
    /// the planned route. Empty outside of an active ride.
    var recordingPath: [CLLocationCoordinate2D] = []
    @ObservedObject private var unitState = UnitState.shared

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showOverwriteAlert = false

    // Cached derived data — computed once on appear to avoid O(n) work on every body recompute
    @State private var cachedCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedProcessedPoints: [ProcessedPoint] = []
    @State private var cachedMileMarkers: [MileMarker] = []
    @State private var currentMarkerInterval: Double = 0
    @State private var cachedElevationExtremes: (high: TrackPoint, low: TrackPoint)? = nil
    @State private var cachedElevationData: [ProcessedPoint] = []
    @State private var didStartLoad = false
    @State private var panelPage = 0
    /// Held in `@State` (not `@StateObject`) so per-frame scrub updates only
    /// re-render the scrub leaf views (chart rule, footer, map dot), never
    /// this body or the Map content.
    @State private var scrubState = ChartScrubState()

    // Cue Editor state
    @State private var isEditingCues: Bool = false
    @StateObject private var cueEditorHolder = CueEditorHolder()
    /// Which cue group shows on top of each overlapping pin stack, keyed by
    /// stack id. Set on tap so the stack doesn't flash back to its first cue
    /// while the editor briefly clears the selection between picks.
    @State private var cueStackFronts: [CueEntryID: CueEntryID] = [:]
    /// Held in `@State` as a plain class so the per-frame size updates while
    /// the panel is dragged don't re-render the map.
    @State private var cueFraming = CueFramingMetrics()
    /// Live map camera heading. Held in `@State` (NOT `@StateObject`)
    /// deliberately: we want only the small counter-rotating annotation
    /// views (HighlightChevron, MileMarkerArrow) to observe the heading via
    /// `@ObservedObject` and re-render per camera frame. `@StateObject`
    /// would also subscribe the whole RouteDetailView body to every
    /// `objectWillChange`, blowing the frame budget during rotation — the
    /// very thing this ObservableObject was meant to avoid. `@State` keeps
    /// the same reference across rebuilds without subscribing to its
    /// publishers.
    @State private var cameraState = MapCameraState()
    /// Tracks whether this view is currently visible. SwiftUI keeps each tab's
    /// view hierarchy alive across tab switches, and an alive MKMapView keeps
    /// burning CPU/GPU on tile rendering even when offscreen — which makes the
    /// destination tab feel frozen for a beat. Toggling this from onAppear/
    /// onDisappear lets us unmount the Map while the tab is hidden and rebuild
    /// it cheaply when the user returns (cached state is preserved).
    @State private var isOnScreen: Bool = false
    /// Cache key for the shared MapCameraCache. Per-route so opening the
    /// same route from different entry points (Routes tab, RideControlView
    /// sheet, deep link) all land on the same remembered camera.
    private var cameraCacheKey: String { "route.\(route.id.uuidString)" }
    /// Axis-aligned bounding region of what's currently visible. Used to drop
    /// off-screen annotations from the Map's ForEach so long routes (with
    /// hundreds of mile markers / POIs / turn pins) don't render every
    /// annotation. Updated only when the camera settles (frequency: .onEnd)
    /// so mid-gesture frames don't invalidate the Map body. Padded in
    /// `inVisibleRegion` so a small pan doesn't immediately drop a marker.
    @State private var visibleRegion: MKCoordinateRegion? = nil

    var body: some View {
        let _ = unitState.preferences
        GeometryReader { proxy in
        ZStack(alignment: .bottom) {
            if isOnScreen {
            MapReader { mapProxy in
            Map(position: $mapPosition) {
                // Route polyline
                MapPolyline(coordinates: cachedCoordinates)
                    .stroke(.blue, lineWidth: 4)

                // In-progress recording breadcrumb, above the route
                if recordingPath.count >= 2 {
                    MapPolyline(coordinates: recordingPath)
                        .stroke(.purple.opacity(0.65), lineWidth: 4)
                }

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

                // Cue Editor map content (highlight overlay, turn pins,
                // waypoint pins). Extracted so the body's @MapContentBuilder
                // stays small enough for Swift's type-checker.
                if isEditingCues, let editor = cueEditorHolder.viewModel {
                    cueEditorMapContent(editor: editor)
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

                // Mile markers: label is a static capsule at the marker
                // position; the direction arrow is a separate annotation
                // halfway-along-route to the next marker (snapped to a track
                // point) so only the arrow re-renders on camera rotation.
                // Filtered to the visible region (with padding) so a 600-mile
                // route doesn't render all ~1200 markers at once.
                ForEach(visibleMileMarkers, id: \.offset) { _, marker in
                    Annotation("", coordinate: marker.coordinate) {
                        MileMarkerLabel(
                            mile: marker.mile,
                            unitLabel: currentUnits.distance.label)
                    }
                    if let arrowCoord = marker.arrowCoordinate,
                       inVisibleRegion(arrowCoord) {
                        Annotation("", coordinate: arrowCoord) {
                            MileMarkerArrow(
                                camera: cameraState,
                                worldBearing: marker.bearingDegrees)
                        }
                    }
                }

                // Waypoints / POIs — including user edits + user-added POIs
                // from the latest persisted overlay, so a waypoint dropped via
                // the Cue Editor shows up here too. Region-filtered and
                // proximity-clustered so POI-heavy routes don't render every
                // pin individually when zoomed out. Clusters re-use the
                // WaypointPin glyph with stacked copies behind it so the
                // visual stays consistent with single pins.
                let poiClusters = clusterAnnotations(
                    displayedPOIs.filter { inVisibleRegion($0.coordinate) },
                    coordinate: { $0.coordinate })
                ForEach(poiClusters) { cluster in
                    if cluster.items.count == 1 {
                        let poi = cluster.items[0]
                        Annotation(poi.name, coordinate: poi.coordinate) {
                            WaypointPin()
                        }
                    } else {
                        Annotation("", coordinate: cluster.center) {
                            WaypointPinCluster(count: cluster.items.count)
                                .onTapGesture {
                                    zoomToCoordinates(cluster.items.map { $0.coordinate })
                                }
                        }
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
            // Two camera handlers: continuous keeps the arrow/chevron
            // counter-rotation responsive without invalidating the Map body
            // every frame, while .onEnd handles the heavier work (re-bucketing
            // the marker interval, snapshotting the visible region, capturing
            // the camera for tab-switch restore).
            .onMapCameraChange(frequency: .continuous) { context in
                cameraState.heading = context.camera.heading
                // Seed the visible region on first camera frame so the initial
                // render is already filtered — .onEnd doesn't fire until the
                // user actually interacts with the map.
                if visibleRegion == nil {
                    visibleRegion = context.region
                    MapCameraCache.shared.store(context.camera, for: cameraCacheKey)
                    updateMarkerInterval(for: context.region)
                }
                if cueFraming.cameraDistanceScale == nil {
                    calibrateCameraScale(context, proxy: mapProxy)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                handleCameraChange(context)
                calibrateCameraScale(context, proxy: mapProxy)
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
            .overlay {
                MapScrubDot(
                    scrub: scrubState,
                    proxy: mapProxy,
                    coordinateFor: interpolateRouteCoordinate)
            }
            }  // end: MapReader
            } else {
                // Map is unmounted while the tab is hidden — keep the same
                // backdrop so re-appearing doesn't flash white.
                Color(.systemBackground)
            }

            // Editor panel takes over while in cue-editor mode
            if isEditingCues, let editor = cueEditorHolder.viewModel {
                VStack(spacing: 0) {
                    Spacer()
                    CueEditorPanel(viewModel: editor, availableHeight: proxy.size.height)
                        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: {
                            cueFraming.panelHeight = $0
                        }
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
                                    RouteElevationChartView(points: cachedElevationData, scrub: scrubState)
                                    Spacer(minLength: 0)
                                }
                                .tag(1)
                            }
                        }
                        .tabViewStyle(.page(indexDisplayMode: .never))
                        .frame(height: panelState == .expanded ? 170 : (route.elevationGain > 0 ? 70 : 60))
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
        .onGeometryChange(for: CGSize.self) { $0.size } action: {
            cueFraming.mapSize = $0
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
        .onAppear {
            isOnScreen = true
            if !didStartLoad {
                didStartLoad = true
                Task { await loadRouteData() }
            }
            // Restore the user's last camera — including zoom (MapCamera
            // carries `distance`) — from the shared cache so re-opening the
            // route detail from anywhere (tab switch, RideControl sheet,
            // navigation back) lands on the same view. First-ever appearance
            // leaves mapPosition at `.automatic` so the route still auto-fits.
            if let cam = MapCameraCache.shared.camera(for: cameraCacheKey) {
                mapPosition = .camera(cam)
            }
        }
        .onDisappear { isOnScreen = false }
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

    /// Pan/zoom the map to a selected waypoint, offset so the pin sits about a
    /// third of the way down from the top of the visible map, above the
    /// editor panel. Preserves the current map heading since waypoints have
    /// no inherent travel direction.
    private func zoomMapToWaypoint(_ id: UUID?) {
        guard let editor = cueEditorHolder.viewModel,
              let id = id,
              let wp = editor.waypointEntries.first(where: { $0.id == id }) else {
            return
        }
        let heading = cameraState.heading
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

    /// Settled-camera handler: snapshot the visible region for annotation
    /// filtering, cache the camera (incl. zoom) for cross-view restore via
    /// MapCameraCache, and re-bucket the marker interval if the zoom level
    /// changed enough to cross a bucket.
    private func handleCameraChange(_ context: MapCameraUpdateContext) {
        visibleRegion = context.region
        MapCameraCache.shared.store(context.camera, for: cameraCacheKey)
        updateMarkerInterval(for: context.region)
    }

    /// Re-buckets mile markers for the visible span. Does nothing until the route has loaded.
    private func updateMarkerInterval(for region: MKCoordinateRegion) {
        let latRad = region.center.latitude * .pi / 180
        let widthMeters = region.span.longitudeDelta * 111_320 * cos(latRad)
        let heightMeters = region.span.latitudeDelta * 111_320
        let interval = mapZoomMarkerInterval(visibleMeters: max(widthMeters, heightMeters))
        guard interval != currentMarkerInterval, !cachedProcessedPoints.isEmpty else { return }
        currentMarkerInterval = interval
        let points = cachedProcessedPoints
        Task.detached(priority: .userInitiated) {
            let markers = computeMileMarkers(points: points, interval: interval)
            await MainActor.run {
                if currentMarkerInterval == interval { cachedMileMarkers = markers }
            }
        }
    }

    /// Returns true when `coord` is inside the current visible region inflated
    /// by ~50% on each axis. The buffer lets the user pan up to half a screen
    /// before any marker drops out — by then `.onEnd` will have refreshed
    /// `visibleRegion`. nil region (initial frame) is treated as "include
    /// everything" until the first camera update lands.
    private func inVisibleRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let r = visibleRegion else { return true }
        let latPad = r.span.latitudeDelta
        let lonPad = r.span.longitudeDelta
        return abs(coord.latitude - r.center.latitude) <= latPad
            && abs(coord.longitude - r.center.longitude) <= lonPad
    }

    /// Mile markers filtered to the visible region. Indexed-enumerated so the
    /// ForEach `id: \.offset` keeps stable identity across filter changes —
    /// `offset` is the marker's index in `cachedMileMarkers`, not in the
    /// filtered subset.
    private var visibleMileMarkers: [EnumeratedSequence<[MileMarker]>.Element] {
        Array(cachedMileMarkers.enumerated()).filter {
            inVisibleRegion($0.element.coordinate)
        }
    }

    /// One proximity-merged cluster of map annotations. Used for turn cues,
    /// route-map waypoints, and cue-editor waypoints — generic over the
    /// underlying item so a single clustering algorithm covers all three.
    /// `id` carries the first item's id so the cluster's SwiftUI identity
    /// stays stable while the user pans (as long as that lead item stays in
    /// the cluster).
    fileprivate struct AnnotationCluster<Item: Identifiable>: Identifiable {
        let id: Item.ID
        let center: CLLocationCoordinate2D
        let items: [Item]
    }

    /// True when the visible map span is short enough that the user is
    /// clearly looking at street-level detail — at that zoom we want every
    /// pin individually instead of cluster icons, even if multiple turns sit
    /// on the same intersection (loops, double-backs). 500 m visible span is
    /// roughly where individual streets stay legible on a phone.
    private var isZoomedIn: Bool {
        guard let r = visibleRegion else { return false }
        let latMeters = r.span.latitudeDelta * 111_320
        let lonMeters = r.span.longitudeDelta * 111_320
            * cos(r.center.latitude * .pi / 180)
        return max(latMeters, lonMeters) < 500
    }

    /// Greedy proximity-clustering. Threshold is a fraction of the visible
    /// span so the cluster radius scales with zoom — at zoomed-out levels
    /// many items collapse into one icon. When the user has zoomed in past
    /// `isZoomedIn` we bail out and emit one cluster per item, so individual
    /// turns/POIs are always visible at street level. Center is the
    /// geographic midpoint of the cluster's items.
    private func clusterAnnotations<Item: Identifiable>(
        _ items: [Item],
        coordinate: (Item) -> CLLocationCoordinate2D
    ) -> [AnnotationCluster<Item>] {
        // Zoomed-in or pre-first-frame → render every item as its own pin.
        guard !isZoomedIn else {
            return items.map {
                AnnotationCluster(id: $0.id, center: coordinate($0), items: [$0])
            }
        }
        // 5% of the map's short side ≈ 20 pt on a phone, roughly a pin's
        // diameter, which is the threshold below which two pins would
        // visually overlap.
        return groupByProximity(items, coordinate: coordinate, shortSideFraction: 0.05)
    }

    /// Zoomed-in turn pins that would still sit on top of each other, grouped
    /// so each group renders as one tappable stack. Looser than the cluster
    /// threshold (≈ 30 pt) since a pin's tap frame is wider than its dot.
    private func stackOverlappingPins<Item: Identifiable>(
        _ items: [Item],
        coordinate: (Item) -> CLLocationCoordinate2D
    ) -> [AnnotationCluster<Item>] {
        groupByProximity(items, coordinate: coordinate, shortSideFraction: 0.08)
    }

    /// The threshold is a straight-line distance in meters, taken as a fraction
    /// of the visible region's shorter side, so it's the same in every
    /// direction no matter the map's shape or rotation.
    private func groupByProximity<Item: Identifiable>(
        _ items: [Item],
        coordinate: (Item) -> CLLocationCoordinate2D,
        shortSideFraction: Double
    ) -> [AnnotationCluster<Item>] {
        guard let r = visibleRegion else {
            return items.map {
                AnnotationCluster(id: $0.id, center: coordinate($0), items: [$0])
            }
        }
        let cosLat = cos(r.center.latitude * .pi / 180)
        let shortSide = min(r.span.latitudeDelta * 111_320, r.span.longitudeDelta * 111_320 * cosLat)
        let threshold = shortSide * shortSideFraction
        let meters = { (a: CLLocationCoordinate2D, b: CLLocationCoordinate2D) -> Double in
            let dLat = (a.latitude - b.latitude) * 111_320
            let dLon = (a.longitude - b.longitude) * 111_320 * cosLat
            return sqrt(dLat * dLat + dLon * dLon)
        }

        var clusters: [AnnotationCluster<Item>] = []
        for item in items {
            let c = coordinate(item)
            if let idx = clusters.firstIndex(where: { meters($0.center, c) <= threshold }) {
                var merged = clusters[idx].items
                merged.append(item)
                let avgLat = merged.reduce(0.0) { $0 + coordinate($1).latitude } / Double(merged.count)
                let avgLon = merged.reduce(0.0) { $0 + coordinate($1).longitude } / Double(merged.count)
                clusters[idx] = AnnotationCluster(
                    id: clusters[idx].id,
                    center: CLLocationCoordinate2D(latitude: avgLat, longitude: avgLon),
                    items: merged)
            } else {
                clusters.append(AnnotationCluster(id: item.id, center: c, items: [item]))
            }
        }
        return clusters
    }

    /// The cue group holding the editor's selection. A list tap can select a
    /// non-anchor member, so this resolves it to the group the pin draws.
    private func selectedCueGroupID(_ editor: CueEditorViewModel) -> CueEntryID? {
        editor.selection.flatMap { sel in
            editor.groupedEntries.first {
                $0.id == sel || $0.members.contains(where: { $0.id == sel })
            }?.id
        }
    }

    /// The group drawn on top of a stack: the selected one if it's in the
    /// stack, else the last one tapped, else the first along the route.
    private func cueStackFront(
        _ stack: AnnotationCluster<CueEntryGroup>,
        editor: CueEditorViewModel
    ) -> CueEntryID {
        let ids = stack.items.map(\.id)
        if let sel = selectedCueGroupID(editor), ids.contains(sel) { return sel }
        if let last = cueStackFronts[stack.id], ids.contains(last) { return last }
        return stack.id
    }

    /// First tap on a stack selects its front cue. Tapping the selected front
    /// again moves to the next cue, wrapping back around to the first.
    private func handleCueStackTap(
        _ stack: AnnotationCluster<CueEntryGroup>,
        tapped: CueEntryID,
        editor: CueEditorViewModel
    ) {
        let ids = stack.items.map(\.id)
        let front = cueStackFront(stack, editor: editor)
        var target = tapped
        if tapped == front, selectedCueGroupID(editor) == front,
           let i = ids.firstIndex(of: front) {
            target = ids[(i + 1) % ids.count]
        }
        cueStackFronts[stack.id] = target
        editor.select(target)
    }

    /// Tap target for a multi-item cluster — animates the camera to a region
    /// that just contains the cluster's items (with breathing room) so the
    /// cluster fans out into individual pins.
    private func zoomToCoordinates(_ coords: [CLLocationCoordinate2D]) {
        let lats = coords.map(\.latitude)
        let lons = coords.map(\.longitude)
        guard let minLat = lats.min(), let maxLat = lats.max(),
              let minLon = lons.min(), let maxLon = lons.max() else { return }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2)
        // Floor the span so we don't zoom in absurdly far on a tight cluster.
        let span = MKCoordinateSpan(
            latitudeDelta: max((maxLat - minLat) * 2.5, 0.002),
            longitudeDelta: max((maxLon - minLon) * 2.5, 0.002))
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .region(MKCoordinateRegion(center: center, span: span))
        }
    }

    @MapContentBuilder
    private func cueEditorMapContent(editor: CueEditorViewModel) -> some MapContent {
        // Highlight overlay for the selected turn (thick white polyline +
        // travel-direction chevrons at each end, counter-rotated against the
        // live map heading so they stay aligned with the route). Resolved
        // through the cue group so a non-anchor member selection still
        // highlights the first-pass anchor — keeps the visual consistent
        // with the displayed pin and badge.
        if let selID = editor.selection,
           let selGroup = editor.groupedEntries.first(where: {
               $0.id == selID || $0.members.contains(where: { $0.id == selID })
           }) {
            let selEntry = selGroup.anchor
            let highlight = editor.highlightCoordinates(for: selEntry)
            if highlight.count >= 2 {
                MapPolyline(coordinates: highlight)
                    .stroke(.white.opacity(0.55), lineWidth: 9)
                let startBearing = RouteProcessor.bearing(from: highlight[0], to: highlight[1])
                let endBearing = RouteProcessor.bearing(
                    from: highlight[highlight.count - 2],
                    to: highlight[highlight.count - 1]
                )
                Annotation("", coordinate: highlight[0]) {
                    HighlightChevron(camera: cameraState, worldBearing: startBearing)
                }
                Annotation("", coordinate: highlight[highlight.count - 1]) {
                    HighlightChevron(camera: cameraState, worldBearing: endBearing)
                }
            }
        }

        // Iterate cue *groups* instead of raw entries — a loop hitting the
        // same intersection twice (same direction, same name) collapses to
        // one group and one map pin with a "×N" badge. Zoomed out, nearby
        // groups cluster into one icon that zooms in on tap. Zoomed in, pins
        // that still overlap become one stack that cycles on tap, with the
        // selected group included so it can sit on top of its stack.
        let selectedGroupID = selectedCueGroupID(editor)
        let stacking = isZoomedIn
        let visibleGroups = editor.groupedEntries.filter {
            (stacking || $0.id != selectedGroupID) && inVisibleRegion($0.anchor.turn.coordinate)
        }
        let turnClusters = stacking
            ? stackOverlappingPins(visibleGroups, coordinate: { $0.anchor.turn.coordinate })
            : clusterAnnotations(visibleGroups, coordinate: { $0.anchor.turn.coordinate })
        let selectedIsStacked = turnClusters.contains { cluster in
            cluster.items.count > 1 && cluster.items.contains { $0.id == selectedGroupID }
        }
        ForEach(turnClusters) { cluster in
            if cluster.items.count == 1 {
                let group = cluster.items[0]
                if group.id != selectedGroupID {
                    Annotation("", coordinate: group.anchor.turn.coordinate) {
                        CueEditorTurnPin(
                            editor: editor,
                            entry: group.anchor,
                            countBadge: group.isMultiple ? group.members.count : nil
                        )
                        .onTapGesture { editor.select(group.id) }
                    }
                }
            } else if stacking {
                Annotation("", coordinate: cluster.center) {
                    CueEditorTurnPinStack(
                        editor: editor,
                        groups: cluster.items,
                        frontID: cueStackFront(cluster, editor: editor),
                        onTap: { tapped in
                            handleCueStackTap(cluster, tapped: tapped, editor: editor)
                        }
                    )
                }
            } else {
                Annotation("", coordinate: cluster.center) {
                    // Cluster count = total underlying turns, not group
                    // count, so the stacked-disc indicator scales with the
                    // actual visual density.
                    let totalCount = cluster.items.reduce(0) { $0 + $1.members.count }
                    MapPinCluster(count: totalCount, color: .indigo)
                        .onTapGesture {
                            zoomToCoordinates(cluster.items.map { $0.anchor.turn.coordinate })
                        }
                }
            }
        }
        // Selected group pin is always rendered as an individual pin (never
        // clustered), even if off-screen — the user explicitly chose it and
        // may pan back to it. A selected group inside a stack is drawn by
        // the stack instead.
        if !selectedIsStacked,
           let selID = selectedGroupID,
           let selGroup = editor.groupedEntries.first(where: { $0.id == selID }) {
            Annotation("", coordinate: selGroup.anchor.turn.coordinate) {
                CueEditorTurnPin(
                    editor: editor,
                    entry: selGroup.anchor,
                    countBadge: selGroup.isMultiple ? selGroup.members.count : nil
                )
                .onTapGesture { editor.select(nil) }
            }
        }

        // Editor-mode waypoint pins (imported + user-added). Same
        // proximity-clustering — clusters re-use the CueEditorWaypointPin
        // glyph with stacked copies behind so the visual stays consistent
        // with single pins. Color follows the items: blue if every entry is
        // user-added, otherwise purple to match the imported color. The
        // selected waypoint is always rendered individually.
        let waypointClusters = clusterAnnotations(
            editor.waypointEntries.filter {
                editor.waypointSelection != $0.id && inVisibleRegion($0.coordinate)
            },
            coordinate: { $0.coordinate })
        ForEach(waypointClusters) { cluster in
            if cluster.items.count == 1 {
                let wp = cluster.items[0]
                Annotation("", coordinate: wp.coordinate) {
                    CueEditorWaypointPin(
                        isSelected: false,
                        isUserAdded: wp.source.isUserAdded
                    )
                    .onTapGesture {
                        handleWaypointPinTap(editor: editor, wpID: wp.id)
                    }
                }
            } else {
                let allUserAdded = cluster.items.allSatisfy { $0.source.isUserAdded }
                Annotation("", coordinate: cluster.center) {
                    CueEditorWaypointPinCluster(
                        count: cluster.items.count,
                        isAllUserAdded: allUserAdded
                    )
                    .onTapGesture {
                        zoomToCoordinates(cluster.items.map { $0.coordinate })
                    }
                }
            }
        }
        if let selWPID = editor.waypointSelection,
           let selWP = editor.waypointEntries.first(where: { $0.id == selWPID }) {
            Annotation("", coordinate: selWP.coordinate) {
                CueEditorWaypointPin(
                    isSelected: true,
                    isUserAdded: selWP.source.isUserAdded
                )
                .onTapGesture {
                    handleWaypointPinTap(editor: editor, wpID: selWP.id)
                }
            }
        }
    }

    /// Tap behavior for a waypoint pin — gated on placement mode and split
    /// out of the Map closure to keep the MapContentBuilder small.
    private func handleWaypointPinTap(editor: CueEditorViewModel, wpID: UUID) {
        guard editor.placementMode == .none else { return }
        if editor.waypointSelection == wpID {
            editor.selectWaypoint(nil)
        } else {
            editor.selectWaypoint(wpID)
        }
    }

    /// POIs to show on the map outside the editor — resolves the live overlay
    /// against the imported waypoints. Mid-ride callers that don't pass
    /// `routeStore` fall back to the navigation-captured route.
    private var displayedPOIs: [DisplayedPOI] {
        let liveRoute: Route = routeStore.flatMap { $0.routes.first(where: { $0.id == route.id }) } ?? route
        let edits = liveRoute.cueEdits
        var result: [DisplayedPOI] = []
        for wp in (liveRoute.waypoints ?? []).filter({ $0.kind == .poi }) {
            let d = edits?.poiDecisions[wp.id]
            if d?.status == .skipped { continue }
            let name = d?.titleOverride ?? wp.name
            let lat = d?.latitudeOverride ?? wp.lat
            let lon = d?.longitudeOverride ?? wp.lon
            result.append(DisplayedPOI(
                id: wp.id,
                name: name,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lon)
            ))
        }
        for added in edits?.addedPOIs ?? [] {
            result.append(DisplayedPOI(
                id: added.id,
                name: added.name,
                coordinate: CLLocationCoordinate2D(latitude: added.lat, longitude: added.lon)
            ))
        }
        return result
    }

    /// Pan/zoom the map so the selected turn's whole highlighted section,
    /// chevrons included, fits in the part of the map above the editor panel,
    /// oriented so the rider's approach heading points "up".
    private func zoomMapToSelection(_ sel: CueEntryID?) {
        guard let editor = cueEditorHolder.viewModel,
              let id = sel,
              let entry = editor.allEntries.first(where: { $0.id == id }) else {
            return
        }
        let heading = editor.inboundBearing(for: entry)
        let origin = entry.turn.coordinate
        let h = heading * .pi / 180
        let cosLat = cos(origin.latitude * .pi / 180)

        // Section bounds in meters along the screen's axes once the camera
        // turns heading-up: u to the right, v up.
        var minU = 0.0, maxU = 0.0, minV = 0.0, maxV = 0.0
        for c in editor.highlightCoordinates(for: entry) {
            let x = (c.longitude - origin.longitude) * 111_320 * cosLat
            let y = (c.latitude - origin.latitude) * 111_320
            let u = x * cos(h) - y * sin(h)
            let v = x * sin(h) + y * cos(h)
            minU = min(minU, u); maxU = max(maxU, u)
            minV = min(minV, v); maxV = max(maxV, v)
        }

        // Padding keeps the chevrons, pins and map controls off the edges. The
        // minimum span stops a tight turn from zooming in to a single building.
        let edgePadding: CGFloat = 48
        let minSpanMeters = 120.0
        let mapSize = cueFraming.mapSize
        let panelHeight = cueFraming.panelHeight
        let freeWidth = Double(max(mapSize.width - 2 * edgePadding, 100))
        let freeHeight = Double(max(mapSize.height - panelHeight - 2 * edgePadding, 100))
        let metersPerPoint = max(
            max(maxU - minU, minSpanMeters) / freeWidth,
            max(maxV - minV, minSpanMeters) / freeHeight)

        // The camera centers on the full map, so put the section's middle half
        // a panel height above that to center it in the uncovered area.
        let midU = (minU + maxU) / 2
        let midV = (minV + maxV) / 2 - Double(panelHeight) / 2 * metersPerPoint
        let x = midU * cos(h) + midV * sin(h)
        let y = -midU * sin(h) + midV * cos(h)
        let target = CLLocationCoordinate2D(
            latitude: origin.latitude + y / 111_320,
            longitude: origin.longitude + x / (111_320 * cosLat))

        let camera = MapCamera(
            centerCoordinate: target,
            distance: metersPerPoint * (cueFraming.cameraDistanceScale ?? 900),
            heading: heading,
            pitch: 0
        )
        withAnimation(.easeInOut(duration: 0.4)) {
            mapPosition = .camera(camera)
        }
    }

    /// Measure how camera distance relates to on-screen scale by projecting a
    /// known 100 m onto the live map, so cue framing doesn't have to guess
    /// MapKit's field of view. Skipped while pitched, where scale varies
    /// across the screen.
    private func calibrateCameraScale(_ context: MapCameraUpdateContext, proxy: MapProxy) {
        guard context.camera.pitch < 5 else { return }
        let center = context.camera.centerCoordinate
        let north = shiftedCoordinate(from: center, distanceMeters: 100, bearingDegrees: 0)
        guard let a = proxy.convert(center, to: .local),
              let b = proxy.convert(north, to: .local) else { return }
        let points = hypot(b.x - a.x, b.y - a.y)
        guard points > 1 else { return }
        cueFraming.cameraDistanceScale = context.camera.distance / (100 / Double(points))
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

    /// Two-phase background load: publish the plain route line as soon as
    /// the coordinates are mapped, then the derived data (processed points,
    /// mile markers, elevation extremes, chart) when it finishes building.
    private func loadRouteData() async {
        let route = route
        let minElevDiff = minElevDiff

        let coords = await Task.detached(priority: .userInitiated) {
            route.points.map {
                CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
            }
        }.value
        cachedCoordinates = coords

        let built = await Task.detached(priority: .userInitiated) { () -> RouteDetailCache in
            let pts = route.points
            var processed: [ProcessedPoint] = []
            var markers: [MileMarker] = []
            if pts.count >= 2 {
                var cumDist: Double = 0
                processed.reserveCapacity(pts.count)
                for i in 0..<pts.count {
                    if i > 0 {
                        let prev = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
                        let cur  = CLLocation(latitude: pts[i].lat,     longitude: pts[i].lon)
                        cumDist += cur.distance(from: prev)
                    }
                    processed.append(ProcessedPoint(
                        coordinate: coords[i],
                        elevation: pts[i].elevation,
                        distanceFromStart: cumDist,
                        bearingToNext: 0))
                }
                markers = computeMileMarkers(points: processed)
            }

            var extremes: (high: TrackPoint, low: TrackPoint)? = nil
            let withElev = pts.filter { $0.elevation != nil }
            if let highest = withElev.max(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
               let lowest  = withElev.min(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
               let highElev = highest.elevation,
               let lowElev  = lowest.elevation,
               highElev - lowElev >= minElevDiff {
                extremes = (highest, lowest)
            }

            return RouteDetailCache(
                processedPoints: processed,
                mileMarkers: markers,
                elevationExtremes: extremes,
                elevationData: buildRouteElevationData(from: route))
        }.value

        cachedProcessedPoints = built.processedPoints
        // The first camera frame may have come before the route loaded, so
        // size the markers for it now instead of showing the default spacing.
        if let region = visibleRegion { updateMarkerInterval(for: region) }
        if currentMarkerInterval == 0 { cachedMileMarkers = built.mileMarkers }
        cachedElevationExtremes = built.elevationExtremes
        cachedElevationData = built.elevationData
    }

    /// Binary-search the processed points' cumulative distances, then
    /// interpolate within the bracketing segment.
    private func interpolateRouteCoordinate(at targetDist: Double) -> CLLocationCoordinate2D? {
        let pts = cachedProcessedPoints
        guard pts.count >= 2 else { return nil }
        guard targetDist < pts[pts.count - 1].distanceFromStart else {
            return pts.last?.coordinate
        }

        var lo = 0, hi = pts.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if pts[mid].distanceFromStart < targetDist { lo = mid } else { hi = mid }
        }
        let seg = pts[hi].distanceFromStart - pts[lo].distanceFromStart
        let fraction = seg > 0 ? (targetDist - pts[lo].distanceFromStart) / seg : 0
        let a = pts[lo].coordinate
        let b = pts[hi].coordinate
        return CLLocationCoordinate2D(
            latitude: a.latitude + fraction * (b.latitude - a.latitude),
            longitude: a.longitude + fraction * (b.longitude - a.longitude))
    }
}

/// Everything the background build produces for the route map, published to
/// the view in one main-actor hop.
private struct RouteDetailCache {
    let processedPoints: [ProcessedPoint]
    let mileMarkers: [MileMarker]
    let elevationExtremes: (high: TrackPoint, low: TrackPoint)?
    let elevationData: [ProcessedPoint]
}

/// Minimal POI shape for the default route-detail map. We keep our own struct
/// (rather than reusing `RoutePOI`) because we don't need the route-distance
/// metadata to render a pin.
private struct DisplayedPOI: Identifiable {
    let id: UUID
    let name: String
    let coordinate: CLLocationCoordinate2D
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


/// Sizes the cue editor needs to frame a selected turn. A plain class, not
/// observable, so writing to it never re-renders anything.
final class CueFramingMetrics {
    var mapSize: CGSize = .zero
    var panelHeight: CGFloat = 0
    /// Camera distance divided by meters per point at pitch 0, measured from
    /// the live map. Nil until the map has drawn a frame.
    var cameraDistanceScale: Double?
}
