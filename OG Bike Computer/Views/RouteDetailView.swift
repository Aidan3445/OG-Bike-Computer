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
    @State private var cachedProcessedPoints: [ProcessedPoint] = []
    @State private var cachedMileMarkers: [MileMarker] = []
    @State private var currentMarkerInterval: Double = 0
    @State private var cachedElevationExtremes: (high: TrackPoint, low: TrackPoint)? = nil
    @State private var cachedElevationData: [ProcessedPoint] = []
    @State private var panelPage = 0
    @State private var scrubDistance: Double? = nil
    @State private var scrubCoordinate: CLLocationCoordinate2D? = nil

    // Cue Editor state
    @State private var isEditingCues: Bool = false
    @StateObject private var cueEditorHolder = CueEditorHolder()
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
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                handleCameraChange(context)
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
        .onAppear {
            isOnScreen = true
            if cachedCoordinates.isEmpty { buildRouteCache() }
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
        let heading = cameraState.heading
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

    /// Settled-camera handler: snapshot the visible region for annotation
    /// filtering, cache the camera (incl. zoom) for cross-view restore via
    /// MapCameraCache, and re-bucket the marker interval if the zoom level
    /// changed enough to cross a bucket.
    private func handleCameraChange(_ context: MapCameraUpdateContext) {
        visibleRegion = context.region
        MapCameraCache.shared.store(context.camera, for: cameraCacheKey)

        let region = context.region
        let latRad = region.center.latitude * .pi / 180
        let cosLat = cos(latRad)
        let widthMeters = region.span.longitudeDelta * 111_320 * cosLat
        let heightMeters = region.span.latitudeDelta * 111_320
        let visibleMeters = max(widthMeters, heightMeters)
        let interval = mapZoomMarkerInterval(visibleMeters: visibleMeters)
        if interval != currentMarkerInterval && !cachedProcessedPoints.isEmpty {
            currentMarkerInterval = interval
            cachedMileMarkers = computeMileMarkers(
                points: cachedProcessedPoints, interval: interval)
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
        guard let r = visibleRegion, !isZoomedIn else {
            return items.map {
                AnnotationCluster(id: $0.id, center: coordinate($0), items: [$0])
            }
        }
        // 3% of the visible span ≈ 20 pt on a phone-sized map at most zooms,
        // roughly a pin's diameter, which is the threshold below which two
        // pins would visually overlap.
        let latThreshold = r.span.latitudeDelta * 0.03
        let lonThreshold = r.span.longitudeDelta * 0.03

        var clusters: [AnnotationCluster<Item>] = []
        for item in items {
            let c = coordinate(item)
            if let idx = clusters.firstIndex(where: { existing in
                abs(existing.center.latitude - c.latitude) <= latThreshold
                    && abs(existing.center.longitude - c.longitude) <= lonThreshold
            }) {
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

    /// At zoomed-in levels, build a map from each turn entry's id to a
    /// "display coordinate" that fans out colocated turns along their own
    /// approach to the intersection. Loops and double-backs put two or more
    /// turns at the same physical coordinate; if we render them all at the
    /// exact same point the pins stack into one tap target. Solution: keep
    /// the first turn in each colocated group at its real coordinate, and
    /// walk every subsequent turn back along the route by `pinSpacingMeters`
    /// per index — so the i-th turn appears `i * spacing` meters before its
    /// own pass through the intersection.
    ///
    /// Returns an empty dictionary when zoomed out (clustering handles
    /// overlaps there) or when the route cache is not yet built.
    private func computeColocatedTurnOffsets(_ entries: [CueEntry]) -> [CueEntryID: CLLocationCoordinate2D] {
        guard isZoomedIn, !cachedProcessedPoints.isEmpty else { return [:] }
        // Two turns within this much of each other are treated as "the same
        // intersection" — tight enough that they'd visually overlap, loose
        // enough to catch GPS jitter between repeated passes.
        let colocationMeters: Double = 10
        // How far apart the offset pins sit along the route. Visible at
        // street zoom without overshooting beyond the intersection.
        let pinSpacingMeters: Double = 18

        // Group by route-distance order so the "first pass" gets the
        // real-coordinate slot and later passes fan back.
        let sorted = entries.sorted { $0.turn.distanceFromStart < $1.turn.distanceFromStart }

        var offsets: [CueEntryID: CLLocationCoordinate2D] = [:]
        var i = 0
        while i < sorted.count {
            let anchor = sorted[i].turn.coordinate
            var j = i + 1
            while j < sorted.count,
                  approxMeters(anchor, sorted[j].turn.coordinate) <= colocationMeters {
                j += 1
            }
            if j - i > 1 {
                for k in 1..<(j - i) {
                    let entry = sorted[i + k]
                    if let coord = walkBackAlongRoute(
                        fromIndex: entry.turn.index,
                        meters: Double(k) * pinSpacingMeters
                    ) {
                        offsets[entry.id] = coord
                    }
                }
            }
            i = j
        }
        return offsets
    }

    /// Approximate flat-earth distance between two coordinates. Plenty for
    /// the few-meters comparisons used to detect colocated turns.
    private func approxMeters(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let dLat = (a.latitude - b.latitude) * 111_320
        let dLon = (a.longitude - b.longitude) * 111_320
            * cos(a.latitude * .pi / 180)
        return sqrt(dLat * dLat + dLon * dLon)
    }

    /// Walk backward through the processed-route points from `fromIndex`
    /// until we've covered `meters` of along-route distance, then linearly
    /// interpolate between the bracketing points for a precise coordinate.
    /// Clamps to the start of the route if `meters` exceeds available
    /// distance.
    private func walkBackAlongRoute(fromIndex: Int, meters: Double) -> CLLocationCoordinate2D? {
        let pts = cachedProcessedPoints
        guard !pts.isEmpty else { return nil }
        let start = min(max(fromIndex, 0), pts.count - 1)
        let target = pts[start].distanceFromStart - meters
        if target <= pts[0].distanceFromStart { return pts[0].coordinate }
        var i = start
        while i > 0 && pts[i].distanceFromStart > target {
            i -= 1
        }
        let a = pts[i]
        let b = i + 1 < pts.count ? pts[i + 1] : a
        let segLen = b.distanceFromStart - a.distanceFromStart
        let ratio = segLen > 0 ? (target - a.distanceFromStart) / segLen : 0
        let lat = a.coordinate.latitude
            + (b.coordinate.latitude - a.coordinate.latitude) * ratio
        let lon = a.coordinate.longitude
            + (b.coordinate.longitude - a.coordinate.longitude) * ratio
        return CLLocationCoordinate2D(latitude: lat, longitude: lon)
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
        // one group and one map pin with a "×N" badge. Across groups,
        // zoomed-out levels still cluster into stacked icons; zoomed-in
        // levels fan out cross-direction colocations via
        // `computeColocatedTurnOffsets`.
        let selectedGroupID: CueEntryID? = editor.selection.flatMap { sel in
            editor.groupedEntries.first {
                $0.id == sel || $0.members.contains(where: { $0.id == sel })
            }?.id
        }
        let visibleGroups = editor.groupedEntries.filter {
            $0.id != selectedGroupID && inVisibleRegion($0.anchor.turn.coordinate)
        }
        // The offset helper still consumes [CueEntry]; group.anchor.id ==
        // group.id, so the resulting offset map is also keyed by group id.
        let turnOffsets = computeColocatedTurnOffsets(visibleGroups.map { $0.anchor })
        let turnClusters = clusterAnnotations(
            visibleGroups,
            coordinate: { $0.anchor.turn.coordinate })
        ForEach(turnClusters) { cluster in
            if cluster.items.count == 1 {
                let group = cluster.items[0]
                let displayCoord = turnOffsets[group.id] ?? group.anchor.turn.coordinate
                Annotation("", coordinate: displayCoord) {
                    CueEditorTurnPin(
                        editor: editor,
                        entry: group.anchor,
                        countBadge: group.isMultiple ? group.members.count : nil
                    )
                    .onTapGesture { editor.select(group.id) }
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
        // may pan back to it. Looked up by group identity so a list tap on a
        // non-anchor member still highlights the right pin.
        if let sel = editor.selection,
           let selGroup = editor.groupedEntries.first(where: {
               $0.id == sel || $0.members.contains(where: { $0.id == sel })
           }) {
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
            cachedProcessedPoints = processed
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

