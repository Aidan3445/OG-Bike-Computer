//
//  RideDetailView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import SwiftUI
import MapKit
import CoreLocation
import Charts
import AppIntents
import HealthKit

struct RideDetailView: View {
    let ride: RideSummary
    let rideStore: RideStore
    @ObservedObject private var unitState = UnitState.shared
    @ObservedObject private var uploadManager = UploadManager.shared
    @Environment(\.dismiss) private var dismiss

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showShareSheet = false
    @State private var isUploadingToStrava = false
    @State private var showFinalizeConfirm = false
    @State private var showDiscardConfirm = false
    @State private var uploadError: String?
    @State private var heldRideError: String?
    @State private var isContinuing = false
    @ObservedObject private var connectivity = ConnectivityManager.shared
    /// Downsampled plain route line, published as soon as the track decodes so
    /// the map has immediate content while colored segments build in the
    /// background. Hidden once `coloredSegments` arrives.
    @State private var simpleRoute: [CLLocationCoordinate2D] = []
    @State private var coloredSegments: [ColoredSegment] = []
    /// Coarser color/coordinate resolution used when zoomed far out, where
    /// fine segments are visually indistinguishable but expensive to render.
    @State private var coarseSegments: [ColoredSegment] = []
    @State private var useCoarseSegments = false
    /// Pairs of (lastPointBefore, firstPointAfter) for every elapsed-time gap
    /// larger than `pauseJumpGapSeconds` — rendered as dashed grey to visually
    /// distinguish pause/hold jumps from actively-ridden segments.
    @State private var pauseJumps: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    @State private var mileMarkers: [MileMarker] = []
    @State private var currentMarkerInterval: Double = 0
    /// Live map heading, updated from `onMapCameraChange`. Held in `@State`
    /// (NOT `@StateObject`) deliberately — we want only the small annotation
    /// views (MileMarkerArrow, HighlightChevron) to observe the heading via
    /// `@ObservedObject` and re-render per camera frame. `@StateObject` here
    /// would also subscribe the whole RideDetailView body to every heading
    /// change, blowing past the 16ms frame budget on each rotation tick.
    /// `@State` holds the same reference across rebuilds without subscribing
    /// to the object's publishers.
    @State private var cameraState = MapCameraState()
    @State private var chartData: [ChartDataPoint] = []
    @State private var chartHasHR = false
    @State private var chartHasPower = false
    @State private var panelPage = 0
    /// Held in `@State` (not `@StateObject`) like `cameraState` — only the
    /// scrub leaf views (chart rule, footer, map dot) observe it, so per-frame
    /// scrub updates never invalidate this view's body or the Map content.
    @State private var scrubState = ChartScrubState()
    @State private var allLocations: [CLLocation] = []
    /// Cumulative along-track distance per point, parallel to `allLocations`.
    /// Lets scrubbing binary-search instead of re-walking the whole track.
    @State private var cumulativeDistances: [Double] = []
    @State private var didStartLoad = false
    @State private var hasStravaAuth = false
    @State private var gpxExportURL: URL?
    @State private var isExportingGPX = false
    /// Unmount the Map while the tab is hidden — see RouteDetailView for the
    /// rationale. SwiftUI keeps tab content alive across switches, and an
    /// alive MKMapView keeps burning CPU/GPU rendering tiles offscreen, which
    /// makes the destination tab feel frozen for a beat.
    @State private var isOnScreen: Bool = false
    /// Cache key for MapCameraCache. Per-ride so opening the same ride
    /// from multiple paths lands on the same remembered camera + zoom.
    private var cameraCacheKey: String { "ride.\(ride.id.uuidString)" }
    /// Visible-region snapshot used to filter off-screen mile markers on long
    /// rides. Updated on camera-settle (.onEnd) so mid-gesture frames don't
    /// invalidate the Map body. See `inVisibleRegion`.
    @State private var visibleRegion: MKCoordinateRegion? = nil

    var body: some View {
        let _ = unitState.preferences
        ZStack(alignment: .bottom) {
            if isOnScreen {
            MapReader { mapProxy in
            Map(position: $mapPosition) {
                // Plain line until the colored segments finish building, then
                // colored polylines filtered to the visible region (with a
                // 50% pad so small pans mid-gesture don't drop edge segments).
                if coloredSegments.isEmpty {
                    if !simpleRoute.isEmpty {
                        MapPolyline(coordinates: simpleRoute)
                            .stroke(.blue, lineWidth: 4)
                    }
                } else {
                    ForEach(visibleColoredSegments) { seg in
                        MapPolyline(coordinates: seg.coords)
                            .stroke(seg.color, lineWidth: 4)
                    }
                }
                // Pause/hold jumps (long elapsed-time gaps) drawn as dashed grey.
                ForEach(Array(pauseJumps.enumerated()), id: \.offset) { _, pair in
                    MapPolyline(coordinates: [pair.0, pair.1])
                        .stroke(Color.gray, style: StrokeStyle(lineWidth: 3, dash: [4, 3]))
                }

                if let first = startCoord {
                    Annotation("Start", coordinate: first) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let last = endCoord {
                    Annotation("End", coordinate: last) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                if let peaks = elevationExtremes {
                    Annotation("", coordinate: peaks.high.coordinate) {
                        VStack(spacing: 2) {
                            Text(formatElevation(peaks.high.elevation))
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

                    Annotation("", coordinate: peaks.low.coordinate) {
                        VStack(spacing: 2) {
                            Image(systemName: "triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(.cyan)
                                .rotationEffect(.degrees(180))
                                .opacity(0.5)
                            Text(formatElevation(peaks.low.elevation))
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

                // Mile markers
                mileMarkerAnnotations()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }
            // Continuous handler does only the cheap per-frame work (arrow
            // counter-rotation via cameraState). Heavier work — region
            // snapshot for annotation filtering, marker interval bucket,
            // camera cache for tab-switch restore — runs on .onEnd so the
            // Map body doesn't invalidate mid-gesture.
            .onMapCameraChange(frequency: .continuous) { context in
                cameraState.heading = context.camera.heading
                if visibleRegion == nil {
                    visibleRegion = context.region
                    useCoarseSegments = visibleSpanMeters(of: context.region) > Self.coarseSegmentSpanMeters
                    MapCameraCache.shared.store(context.camera, for: cameraCacheKey)
                }
            }
            .onMapCameraChange(frequency: .onEnd) { context in
                visibleRegion = context.region
                MapCameraCache.shared.store(context.camera, for: cameraCacheKey)

                let visibleMeters = visibleSpanMeters(of: context.region)
                useCoarseSegments = visibleMeters > Self.coarseSegmentSpanMeters
                let interval = mapZoomMarkerInterval(visibleMeters: visibleMeters)
                if interval != currentMarkerInterval && !allLocations.isEmpty {
                    currentMarkerInterval = interval
                    let locations = allLocations
                    Task.detached(priority: .userInitiated) {
                        let markers = computeRideMileMarkers(locations: locations, interval: interval)
                        await MainActor.run {
                            if currentMarkerInterval == interval { mileMarkers = markers }
                        }
                    }
                }
            }
            .overlay {
                MapScrubDot(
                    scrub: scrubState,
                    proxy: mapProxy,
                    coordinateFor: interpolateCoordinate)
            }
            }  // end: MapReader
            } else {
                Color(.systemBackground)
            }

            // Stats overlay — 3 states: collapsed (button) → compact (core stats) → expanded (all stats)
            VStack(spacing: 0) {
                Spacer()

                statsPanel()
            }
        }
        .safeAreaInset(edge: .bottom) {
            if ride.onHold && connectivity.isReachable {
                VStack(spacing: 4) {
                    HStack(spacing: 8) {
                        Button {
                            continueHeldRide()
                        } label: {
                            Label(isContinuing ? "Continuing…" : "Continue", systemImage: "hand.raised.fill")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.orange)
                        .disabled(isContinuing)

                        Button {
                            showFinalizeConfirm = true
                        } label: {
                            Label("End & Save", systemImage: "checkmark.circle")
                                .frame(maxWidth: .infinity, minHeight: 44)
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.green)
                        .confirmationDialog("Save this ride?", isPresented: $showFinalizeConfirm, titleVisibility: .visible) {
                            Button("Save Ride") {
                                ConnectivityManager.shared.sendFinalizeHeldRide(summary: ride, rideStore: rideStore)
                                dismiss()
                            }
                            Button("Cancel", role: .cancel) {}
                        } message: {
                            Text("The ride will be saved as complete and you can upload it to Strava.")
                        }
                    }

                    Button(role: .destructive) {
                        showDiscardConfirm = true
                    } label: {
                        Label("Discard Ride", systemImage: "trash")
                            .frame(maxWidth: .infinity, minHeight: 36)
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .confirmationDialog("Discard this ride?", isPresented: $showDiscardConfirm, titleVisibility: .visible) {
                        Button("Discard", role: .destructive) {
                            ConnectivityManager.shared.sendDiscardRide(rideID: ride.id)
                            // Pop the detail screen — the held ride no longer exists, the
                            // view above us would otherwise read a now-orphaned `ride`.
                            dismiss()
                        }
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("The held ride will be permanently deleted. This cannot be undone.")
                    }
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(.regularMaterial)
            }
        }
        .alert("Could not continue ride", isPresented: Binding(
            get: { heldRideError != nil },
            set: { if !$0 { heldRideError = nil } }
        )) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(heldRideError ?? "")
        }
        .navigationTitle(ride.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        exportGPXForSharing()
                    } label: {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }
                    .disabled(isExportingGPX)

                    let alreadyOnStrava = ride.uploads?.contains(where: { $0.service == .strava && $0.isComplete }) == true
                    if hasStravaAuth && !alreadyOnStrava {
                        Button {
                            uploadToStrava()
                        } label: {
                            Label("Upload to Strava", systemImage: "figure.outdoor.cycle")
                        }
                        .disabled(isUploadingToStrava)
                    }

                    if let uploads = ride.uploads?.filter({ $0.isComplete }).uniqueByService(),
                       !uploads.isEmpty {
                        Divider()
                        ForEach(uploads) { upload in
                            if let urlString = upload.webURL, let url = URL(string: urlString) {
                                Link(destination: url) {
                                    Label("View on \(upload.service.displayName)", systemImage: "arrow.up.right")
                                }
                            }
                        }
                    }
                } label: {
                    if isUploadingToStrava || isExportingGPX {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let gpxURL = gpxExportURL {
                ShareSheet(activityItems: [gpxURL])
            }
        }
        .alert("Upload Error", isPresented: .init(
            get: { uploadError != nil },
            set: { if !$0 { uploadError = nil } }
        )) {
            Button("OK") { uploadError = nil }
        } message: {
            Text(uploadError ?? "")
        }
        .onAppear {
            isOnScreen = true
            hasStravaAuth = KeychainHelper.loadTokens(for: .strava) != nil
            if !didStartLoad {
                didStartLoad = true
                Task { await loadRideData() }
            }
            // Restore the cached camera (incl. zoom level) from the shared
            // cache so re-opening this ride lands exactly where the user
            // left it.
            if let cam = MapCameraCache.shared.camera(for: cameraCacheKey) {
                mapPosition = .camera(cam)
            }
        }
        .onDisappear { isOnScreen = false }
    }
    
    @MapContentBuilder
    private func mileMarkerAnnotations() -> some MapContent {
        // Label is a static capsule at the marker position; the direction
        // arrow is a separate annotation placed halfway along the route to
        // the next marker so only the arrow re-renders on camera rotation.
        // Filtered to the visible region so a long ride doesn't render every
        // marker at once.
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
    }

    /// Visible-region inflated by ~50% on each axis so a small pan during a
    /// gesture doesn't drop markers from the view before `.onEnd` refreshes
    /// the cached region. nil region treats every marker as visible.
    private func inVisibleRegion(_ coord: CLLocationCoordinate2D) -> Bool {
        guard let r = visibleRegion else { return true }
        return abs(coord.latitude - r.center.latitude) <= r.span.latitudeDelta
            && abs(coord.longitude - r.center.longitude) <= r.span.longitudeDelta
    }

    /// Visible span (~10 km) above which the coarse segment LOD renders —
    /// zoomed out that far, a 4 pt line covers >100 m of track and the fine
    /// color resolution is invisible.
    private static let coarseSegmentSpanMeters: Double = 10_000

    private func visibleSpanMeters(of region: MKCoordinateRegion) -> Double {
        let cosLat = cos(region.center.latitude * .pi / 180)
        let widthMeters = region.span.longitudeDelta * 111_320 * cosLat
        let heightMeters = region.span.latitudeDelta * 111_320
        return max(widthMeters, heightMeters)
    }

    /// Colored polyline segments whose bounding boxes overlap the current
    /// visible region (with a 50% pad on each side). nil region returns
    /// everything — first frame can't be filtered.
    private var visibleColoredSegments: [ColoredSegment] {
        let segments = useCoarseSegments && !coarseSegments.isEmpty
            ? coarseSegments : coloredSegments
        guard let r = visibleRegion else { return segments }
        return segments.filter { $0.bbox.overlaps(r) }
    }

    /// Mile markers filtered to the visible region; `\.offset` keeps stable
    /// ForEach identity across filter changes (it's the index in the full
    /// `mileMarkers`, not in the filtered subset).
    private var visibleMileMarkers: [EnumeratedSequence<[MileMarker]>.Element] {
        Array(mileMarkers.enumerated()).filter {
            inVisibleRegion($0.element.coordinate)
        }
    }
    
    @ViewBuilder
    private func statsPanel() -> some View {
        VStack(spacing: 6) {
            if panelState != .collapsed {
                panelDragHandle()

                TabView(selection: $panelPage) {
                    statsPage()
                        .tag(0)

                    chartsPage()
                        .tag(1)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: panelState == .expanded ? 280 : 200)
                .onChange(of: panelPage) { _, newPage in
                    if newPage == 1 && panelState == .compact {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            panelState = .expanded
                        }
                    }
                }

                panelPageDots()
            } else {
                collapsedPanelButton()
            }
        }
        .padding(.horizontal, panelState != .collapsed ? 16 : 0)
        .padding(.bottom, 8)
        .frame(
            maxWidth: panelState != .collapsed ? .infinity : nil,
            alignment: panelState != .collapsed ? .center : .trailing
        )
        .frame(
            width: panelState != .collapsed ? nil : 48,
            height: panelState != .collapsed ? nil : 48
        )
        .background(
            RoundedRectangle(cornerRadius: panelState != .collapsed ? 16 : 24)
                .fill(.ultraThinMaterial)
                .shadow(radius: 12, y: 4)
        )
        .padding(.horizontal, panelState != .collapsed ? 12 : 0)
        .padding(.bottom, panelState != .collapsed ? 12 : 24)
        .padding(.trailing, panelState != .collapsed ? 0 : 16)
        .frame(
            maxWidth: .infinity,
            alignment: panelState != .collapsed ? .center : .trailing
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if panelState == .collapsed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    panelState = panelPage == 1 ? .expanded : .compact
                }
            }
        }
    }

    private func panelDragHandle() -> some View {
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
                                case .expanded:
                                    panelState = skipsCompact ? .collapsed : .compact
                                case .compact:
                                    panelState = .collapsed
                                case .collapsed:
                                    break
                                }
                            } else {
                                switch panelState {
                                case .collapsed:
                                    panelState = skipsCompact ? .expanded : .compact
                                case .compact:
                                    panelState = .expanded
                                case .expanded:
                                    break
                                }
                            }
                        }
                    }
            )
    }

    @ViewBuilder
    private func statsPage() -> some View {
        VStack(spacing: 8) {
            let columns = [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ]

            let stats = rideStats(compact: panelState == .compact)
            let rows = stats.chunked(into: 3)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if rowIdx > 0 {
                    Divider()
                }

                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(row, id: \.label) { stat in
                        StatItem(label: stat.label, value: stat.value)
                    }
                }
            }

            if hasExtendedStats {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        panelState = panelState == .expanded ? .compact : .expanded
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text(panelState == .expanded ? "Less" : "More")
                            .font(.caption2.weight(.medium))

                        Image(systemName: panelState == .expanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func chartsPage() -> some View {
        VStack(spacing: 4) {
            if !chartData.isEmpty {
                RideChartsView(
                    dataPoints: chartData,
                    hasHeartRate: chartHasHR,
                    hasPower: chartHasPower,
                    scrub: scrubState
                )
            } else {
                Text("No chart data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(height: 140)
            }

            Spacer(minLength: 0)
        }
    }

    private func panelPageDots() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<2, id: \.self) { i in
                Circle()
                    .fill(panelPage == i ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }

    private func collapsedPanelButton() -> some View {
        Image(systemName: "chart.bar.xaxis")
            .font(.system(size: 18, weight: .semibold))
            .foregroundStyle(.primary)
            .padding(.top, 8)
    }

    private func continueHeldRide() {
        guard !isContinuing else { return }
        isContinuing = true

        // Wake the watch app so the continue command lands while the app is foregrounded.
        let config = HKWorkoutConfiguration()
        config.activityType = ride.activityType.hkType
        config.locationType = .outdoor
        HKHealthStore().startWatchApp(with: config) { _, _ in }

        let resumedID = ride.id
        ConnectivityManager.shared.sendContinueHeldRide(summary: ride) { result in
            DispatchQueue.main.async {
                isContinuing = false
                switch result {
                case .success:
                    // ConnectivityManager already drops the held copy on a successful
                    // watch ack, but call delete here too so this view's `ride`
                    // reference can't outlive the store row if the navigation pop
                    // races the async cleanup.
                    if let stale = rideStore.rides.first(where: { $0.id == resumedID }) {
                        rideStore.delete(stale)
                    }
                    dismiss()
                case .failure(let error):
                    heldRideError = error.localizedDescription
                }
            }
        }
    }

    private func uploadToStrava() {
        isUploadingToStrava = true
        Task {
            // Let the menu-dismiss animation finish before upload work starts
            // publishing state changes that re-render the map.
            try? await Task.sleep(for: .milliseconds(400))
            do {
                _ = try await uploadManager.manualUploadToStrava(ride)
            } catch {
                await MainActor.run {
                    uploadError = error.localizedDescription
                }
            }
            await MainActor.run {
                isUploadingToStrava = false
            }
        }
    }

    private var hasExtendedStats: Bool {
        ride.maxSpeed != nil || ride.avgPower != nil || ride.maxPower != nil ||
        ride.avgHeartRate != nil || ride.maxHeartRate != nil ||
        ride.highestElevation != nil || ride.lowestElevation != nil ||
        ride.calories > 0
    }

    private func rideStats(compact: Bool) -> [(label: String, value: String)] {
        var stats: [(label: String, value: String)] = []

        // Core stats — always shown
        stats.append(("Distance", formatDistance(ride.distance)))
        stats.append(("Moving Time", formatTime(ride.movingTime)))
        stats.append(("Avg Speed", formatSpeed(ride.avgSpeed)))
        stats.append(("Elapsed", formatTime(ride.elapsedTime)))
        if let maxSpd = ride.maxSpeed {
            stats.append(("Max Speed", formatSpeed(maxSpd)))
        }

        // Elevation
        if ride.elevationGain > 0 { stats.append(("Elev Gain", formatElevation(ride.elevationGain))) }
        if ride.elevationLoss > 0 { stats.append(("Elev Loss", formatElevation(ride.elevationLoss))) }
        if let high = ride.highestElevation { stats.append(("High Elev", formatElevation(high))) }
        if let low = ride.lowestElevation { stats.append(("Low Elev", formatElevation(low))) }

        guard !compact else { return stats }

        // Heart rate
        if let avgHR = ride.avgHeartRate { stats.append(("Avg HR", "\(Int(avgHR.rounded())) bpm")) }
        if let maxHR = ride.maxHeartRate { stats.append(("Max HR", "\(Int(maxHR.rounded())) bpm")) }

        // Power
        if let avgPwr = ride.avgPower { stats.append(("Avg Power", "\(Int(avgPwr.rounded())) W")) }
        if let maxPwr = ride.maxPower { stats.append(("Max Power", "\(Int(maxPwr.rounded())) W")) }

        // Other
        if ride.calories > 0 { stats.append(("Calories", String(format: "%.0f kcal", ride.calories))) }
        stats.append(("Activity", ride.activityType.rawValue.capitalized))

        return stats
    }

    // MARK: - Track loading

    /// Two-phase background load. Phase 1 decodes the track and publishes a
    /// downsampled plain line so the map has content within one frame budget
    /// of the decode. Phase 2 builds everything expensive — colored segments
    /// at both LODs, mile markers, elevation extremes, chart data.
    private func loadRideData() async {
        let url = rideStore.trackURL(for: ride)

        let loaded = await Task.detached(priority: .userInitiated) { () -> ([CLLocation], [TrackPoint5], [CLLocationCoordinate2D])? in
            guard let data = try? Data(contentsOf: url) else { return nil }
            let pts = TrackEncoder.decodeV5Full(data)
            guard pts.count >= 2 else { return nil }
            let locations = pts.map { pt in
                CLLocation(
                    coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon),
                    altitude: pt.altitude,
                    horizontalAccuracy: 0,
                    verticalAccuracy: 0,
                    timestamp: Date(timeIntervalSince1970: pt.timestamp))
            }
            let simple = downsampleCoordinates(locations.map(\.coordinate), maxPoints: 1000)
            return (locations, pts, simple)
        }.value
        guard let (locations, fullPoints, simple) = loaded else { return }

        allLocations = locations
        startCoord   = locations.first?.coordinate
        endCoord     = locations.last?.coordinate
        simpleRoute  = simple

        let built = await Task.detached(priority: .userInitiated) { () -> RideMapData in
            var cumDist = [Double](repeating: 0, count: locations.count)
            for i in 1..<locations.count {
                cumDist[i] = cumDist[i - 1] + locations[i].distance(from: locations[i - 1])
            }

            // Split into ridden runs at large elapsed-time gaps so the speed-
            // colored polyline doesn't draw a straight line across a pause/
            // hold jump. The gaps themselves render as dashed grey.
            let split = splitAtPauseGaps(locations: locations, gapSeconds: 30)
            let runCount = max(split.runs.count, 1)
            let fine = split.runs.flatMap {
                buildColoredSegments(locations: $0, segmentCount: max(50, 500 / runCount))
            }
            let coarseRaw = split.runs.flatMap {
                buildColoredSegments(locations: $0, segmentCount: max(20, 120 / runCount), colorSteps: 6)
            }
            let coarse = downsampleSegments(coarseRaw, totalPointBudget: 1500)

            let chart = buildRideChartData(points: fullPoints)
            return RideMapData(
                cumulativeDistances: cumDist,
                pauseJumps: split.gaps,
                fineSegments: fine,
                coarseSegments: coarse,
                mileMarkers: computeRideMileMarkers(locations: locations),
                elevationExtremes: computeElevExtremes(locations: locations),
                chartPoints: chart.points,
                chartHasHR: chart.hasHR,
                chartHasPower: chart.hasPower)
        }.value

        cumulativeDistances = built.cumulativeDistances
        pauseJumps          = built.pauseJumps
        coloredSegments     = built.fineSegments
        coarseSegments      = built.coarseSegments
        // A camera-driven re-bucket may have already produced markers at the
        // right interval — don't clobber them with the default-interval set.
        if currentMarkerInterval == 0 { mileMarkers = built.mileMarkers }
        elevationExtremes   = built.elevationExtremes
        chartData           = built.chartPoints
        chartHasHR          = built.chartHasHR
        chartHasPower       = built.chartHasPower
    }

    private func exportGPXForSharing() {
        guard !isExportingGPX else { return }
        isExportingGPX = true
        let store = rideStore
        let ride = ride
        Task.detached(priority: .userInitiated) {
            let url = store.exportGPX(for: ride)
            await MainActor.run {
                isExportingGPX = false
                if let url {
                    gpxExportURL = url
                    showShareSheet = true
                }
            }
        }
    }

    /// Binary-search the precomputed cumulative distances, then interpolate
    /// within the bracketing segment.
    private func interpolateCoordinate(at targetDistance: Double) -> CLLocationCoordinate2D? {
        let cumDist = cumulativeDistances
        guard allLocations.count >= 2, cumDist.count == allLocations.count else { return nil }
        guard targetDistance < cumDist[cumDist.count - 1] else {
            return allLocations.last?.coordinate
        }

        var lo = 0, hi = cumDist.count - 1
        while lo + 1 < hi {
            let mid = (lo + hi) / 2
            if cumDist[mid] < targetDistance { lo = mid } else { hi = mid }
        }
        let seg = cumDist[hi] - cumDist[lo]
        let fraction = seg > 0 ? (targetDistance - cumDist[lo]) / seg : 0
        let a = allLocations[lo].coordinate
        let b = allLocations[hi].coordinate
        return CLLocationCoordinate2D(
            latitude: a.latitude + fraction * (b.latitude - a.latitude),
            longitude: a.longitude + fraction * (b.longitude - a.longitude))
    }
}

/// Everything the background build produces for the ride map, published to
/// the view in one main-actor hop.
private struct RideMapData {
    let cumulativeDistances: [Double]
    let pauseJumps: [(CLLocationCoordinate2D, CLLocationCoordinate2D)]
    let fineSegments: [ColoredSegment]
    let coarseSegments: [ColoredSegment]
    let mileMarkers: [MileMarker]
    let elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    let chartPoints: [ChartDataPoint]
    let chartHasHR: Bool
    let chartHasPower: Bool
}

/// Keep at most `maxPoints` by striding, always preserving the endpoints.
private func downsampleCoordinates(
    _ coords: [CLLocationCoordinate2D],
    maxPoints: Int
) -> [CLLocationCoordinate2D] {
    guard coords.count > maxPoints, maxPoints >= 2 else { return coords }
    let stride = coords.count / maxPoints + 1
    var result: [CLLocationCoordinate2D] = []
    result.reserveCapacity(maxPoints + 1)
    var i = 0
    while i < coords.count {
        result.append(coords[i])
        i += stride
    }
    if let last = coords.last,
       result.last.map({ $0.latitude != last.latitude || $0.longitude != last.longitude }) ?? true {
        result.append(last)
    }
    return result
}

/// Downsample each segment's coordinates so the whole set stays within
/// `totalPointBudget` points, proportionally to segment size.
private func downsampleSegments(
    _ segments: [ColoredSegment],
    totalPointBudget: Int
) -> [ColoredSegment] {
    let totalPoints = segments.reduce(0) { $0 + $1.coords.count }
    guard totalPoints > totalPointBudget else { return segments }
    let keepFraction = Double(totalPointBudget) / Double(totalPoints)
    return segments.map { seg in
        let budget = max(2, Int(Double(seg.coords.count) * keepFraction))
        return ColoredSegment(
            coords: downsampleCoordinates(seg.coords, maxPoints: budget),
            color: seg.color,
            bbox: seg.bbox)
    }
}

// MARK: - Speed coloring

/// Axis-aligned lat/lon bounds, pre-computed once per segment so the
/// per-frame Map body can drop off-screen segments in constant time.
struct SegmentBBox {
    let minLat: Double
    let maxLat: Double
    let minLon: Double
    let maxLon: Double

    static func compute(_ coords: [CLLocationCoordinate2D]) -> SegmentBBox {
        var minLat = 90.0, maxLat = -90.0, minLon = 180.0, maxLon = -180.0
        for c in coords {
            if c.latitude < minLat { minLat = c.latitude }
            if c.latitude > maxLat { maxLat = c.latitude }
            if c.longitude < minLon { minLon = c.longitude }
            if c.longitude > maxLon { maxLon = c.longitude }
        }
        return SegmentBBox(
            minLat: minLat, maxLat: maxLat,
            minLon: minLon, maxLon: maxLon)
    }

    /// True when this bbox overlaps the visible region inflated by
    /// `padFraction` on each side — gives the user some pan room before
    /// segments at the edge drop out (visibleRegion only refreshes on
    /// gesture-end).
    func overlaps(_ region: MKCoordinateRegion, padFraction: Double = 0.5) -> Bool {
        let latPad = region.span.latitudeDelta * (0.5 + padFraction)
        let lonPad = region.span.longitudeDelta * (0.5 + padFraction)
        let visMinLat = region.center.latitude - latPad
        let visMaxLat = region.center.latitude + latPad
        let visMinLon = region.center.longitude - lonPad
        let visMaxLon = region.center.longitude + lonPad
        return !(maxLat < visMinLat || minLat > visMaxLat
                 || maxLon < visMinLon || minLon > visMaxLon)
    }
}

private struct ColoredSegment: Identifiable {
    let id = UUID()
    let coords: [CLLocationCoordinate2D]
    let color: Color
    /// Pre-computed bounding box for visible-region filtering. Long rides
    /// can produce hundreds of segments; computing the bbox once at build
    /// time keeps the Map body's per-render filter O(N).
    let bbox: SegmentBBox
}

/// Splits a track into ridden runs separated by long elapsed-time gaps.
/// Returns both the runs (each ≥1 point) and the gap pairs — adjacent
/// `(lastPointBeforeGap, firstPointAfterGap)` — so the caller can render
/// the gaps differently (e.g. dashed grey) from the ridden segments.
///
/// Runs that are shorter than `minRunMeters` *or* `minRunSeconds` are
/// considered too trivial to draw a dashed connector to — typically a
/// pause-immediately-after-resume blip or GPS jitter — and are dropped
/// from both the runs and the gap list. The underlying track data is
/// untouched on disk; this is purely a render-time filter.
private func splitAtPauseGaps(
    locations: [CLLocation],
    gapSeconds: TimeInterval = 30,
    minRunMeters: Double = 3.048,      // ~10 feet
    minRunSeconds: TimeInterval = 3
) -> (runs: [[CLLocation]], gaps: [(CLLocationCoordinate2D, CLLocationCoordinate2D)]) {
    guard locations.count >= 2 else { return (runs: [locations], gaps: []) }

    // 1. Carve into raw runs at every >gapSeconds break.
    var rawRuns: [[CLLocation]] = []
    var current: [CLLocation] = [locations[0]]
    for i in 1..<locations.count {
        let dt = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)
        if dt > gapSeconds {
            rawRuns.append(current)
            current = [locations[i]]
        } else {
            current.append(locations[i])
        }
    }
    rawRuns.append(current)

    // 2. Keep only runs that are meaningful in both distance and time.
    let meaningfulRuns: [[CLLocation]] = rawRuns.filter { run in
        guard run.count >= 2,
              let first = run.first,
              let last = run.last else { return false }
        let duration = last.timestamp.timeIntervalSince(first.timestamp)
        var dist: Double = 0
        for i in 1..<run.count {
            dist += run[i].distance(from: run[i - 1])
        }
        return duration >= minRunSeconds && dist >= minRunMeters
    }

    // 3. Rebuild gaps as connectors between consecutive *meaningful* runs.
    var gaps: [(CLLocationCoordinate2D, CLLocationCoordinate2D)] = []
    for i in 1..<meaningfulRuns.count {
        guard let prevEnd = meaningfulRuns[i - 1].last?.coordinate,
              let nextStart = meaningfulRuns[i].first?.coordinate else { continue }
        gaps.append((prevEnd, nextStart))
    }

    return (runs: meaningfulRuns, gaps: gaps)
}

/// Splits the track into `segmentCount` equal-sized chunks, computes average speed per chunk,
/// then merges adjacent chunks that share the same quantized color step — so the rendered
/// MapPolyline count equals the number of color *transitions*, not the chunk count.
/// `colorSteps` controls color resolution: 20 gives 5% increments, plenty for a gradient.
private func buildColoredSegments(
    locations: [CLLocation],
    segmentCount: Int = 500,
    colorSteps: Int = 20
) -> [ColoredSegment] {
    guard locations.count >= 2 else { return [] }

    let chunkSize = max(1, locations.count / segmentCount)

    // ── Step 1: compute per-chunk average speed ──────────────────────────────
    // Each chunk's last point == next chunk's first point, so polylines connect.
    var chunks: [(coords: [CLLocationCoordinate2D], avgSpeed: Double)] = []
    var i = 0
    while i < locations.count - 1 {
        let end   = min(i + chunkSize + 1, locations.count)
        let slice = Array(locations[i..<end])

        var totalDist = 0.0, totalTime = 0.0
        for j in 1..<slice.count {
            let d  = slice[j].distance(from: slice[j - 1])
            let dt = slice[j].timestamp.timeIntervalSince(slice[j - 1].timestamp)
            totalDist += d
            if dt > 0 { totalTime += dt }
        }
        chunks.append((coords: slice.map(\.coordinate),
                       avgSpeed: totalTime > 0 ? totalDist / totalTime : 0))
        i += chunkSize
    }

    // ── Step 2: normalize speeds to p10–p90 ──────────────────────────────────
    let speeds = chunks.map(\.avgSpeed).filter { $0 > 0.5 }.sorted()
    guard !speeds.isEmpty else {
        let coords = locations.map(\.coordinate)
        return [ColoredSegment(coords: coords, color: .blue, bbox: SegmentBBox.compute(coords))]
    }
    let p10   = speeds[speeds.count / 10]
    let p90   = speeds[min(speeds.count - 1, speeds.count * 9 / 10)]
    let range = max(p90 - p10, 0.1)

    func stepFor(speed: Double) -> Int {
        let ratio = max(0.0, min(1.0, (speed - p10) / range))
        return Int((ratio * Double(colorSteps - 1)).rounded())
    }

    // ── Step 3: merge adjacent chunks with the same color step ───────────────
    var segments: [ColoredSegment] = []
    var batchCoords = chunks[0].coords
    var batchStep   = stepFor(speed: chunks[0].avgSpeed)

    for chunk in chunks.dropFirst() {
        let step = stepFor(speed: chunk.avgSpeed)
        if step == batchStep {
            // Same color — extend batch, drop duplicate shared endpoint
            batchCoords.append(contentsOf: chunk.coords.dropFirst())
        } else {
            // Color changed — flush current batch, start new one
            segments.append(ColoredSegment(
                coords: batchCoords,
                color:  rideSpeedColor(ratio: Double(batchStep) / Double(colorSteps - 1)),
                bbox:   SegmentBBox.compute(batchCoords)
            ))
            batchCoords = chunk.coords
            batchStep   = step
        }
    }
    if !batchCoords.isEmpty {
        segments.append(ColoredSegment(
            coords: batchCoords,
            color:  rideSpeedColor(ratio: Double(batchStep) / Double(colorSteps - 1)),
            bbox:   SegmentBBox.compute(batchCoords)
        ))
    }
    return segments
}

/// Red → yellow → green gradient.
private func rideSpeedColor(ratio: Double) -> Color {
    if ratio < 0.5 { return Color(red: 1.0, green: ratio * 2,           blue: 0) }
    else           { return Color(red: 1.0 - (ratio - 0.5) * 2, green: 1.0, blue: 0) }
}

// MARK: - Elevation extremes

private func computeElevExtremes(locations: [CLLocation]) -> (high: ElevPoint, low: ElevPoint)? {
    let valid = locations.filter { $0.verticalAccuracy >= 0 }
    guard let high = valid.max(by: { $0.altitude < $1.altitude }),
          let low  = valid.min(by: { $0.altitude < $1.altitude }),
          high.altitude - low.altitude >= 50 else { return nil }
    return (high: ElevPoint(coordinate: high.coordinate, elevation: high.altitude),
            low:  ElevPoint(coordinate: low.coordinate,  elevation: low.altitude))
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

struct ElevPoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
}


