//
//  MultiRideDetailView.swift
//  OG Bike Computer
//

import SwiftUI
import MapKit
import CoreLocation

struct MultiRideDetailView: View {
    let rides: [RideSummary]   // ordered as the user selected
    let rideStore: RideStore
    @ObservedObject private var unitState = UnitState.shared
    @Environment(\.dismiss) private var dismiss

    enum PanelState { case collapsed, compact, expanded }

    static let segmentColors: [Color] = [.blue, .yellow, .indigo, .orange, .green, .red]
    /// Connector gap below which we skip the grey link and just extend the
    /// previous ride's color over to the next start.
    private static let closeConnectorMeters: Double = 75

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var panelPage = 0
    @State private var showShareSheet = false

    @State private var renders: [RideRender] = []
    @State private var connectors: [Connector] = []
    @State private var combinedChart: [ChartDataPoint] = []
    @State private var chartHasHR = false
    @State private var chartHasPower = false
    @State private var scrubDistance: Double? = nil
    @State private var scrubColor: Color = .green

    struct RideRender: Identifiable {
        let id: UUID
        let coords: [CLLocationCoordinate2D]
        let color: Color
        let stat: SegmentStat
    }

    struct Connector: Identifiable {
        let id = UUID()
        let from: CLLocationCoordinate2D
        let to: CLLocationCoordinate2D
        let color: Color
        let dashed: Bool
    }

    struct SegmentStat {
        let name: String
        let distance: Double           // meters
        let movingTime: TimeInterval
        let elapsedTime: TimeInterval
        let elevationGain: Double
        let avgSpeed: Double
        let color: Color
    }

    var body: some View {
        let _ = unitState.preferences
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                ForEach(renders) { r in
                    MapPolyline(coordinates: r.coords)
                        .stroke(r.color, lineWidth: 4)
                }
                ForEach(connectors) { c in
                    if c.dashed {
                        MapPolyline(coordinates: [c.from, c.to])
                            .stroke(c.color, style: StrokeStyle(lineWidth: 3, dash: [6, 4]))
                    } else {
                        MapPolyline(coordinates: [c.from, c.to])
                            .stroke(c.color, lineWidth: 4)
                    }
                }

                if let first = renders.first, let coord = first.coords.first {
                    Annotation("Start", coordinate: coord) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
                if let last = renders.last, let coord = last.coords.last {
                    Annotation("End", coordinate: coord) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }

            VStack(spacing: 0) {
                Spacer()
                statsPanel()
            }
        }
        .navigationTitle("\(rides.count) Rides")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let url = rideStore.exportCombinedGPX(rides: rides) {
                ShareSheet(activityItems: [url])
            }
        }
        .onAppear { buildCache() }
    }

    // MARK: - Stats panel (same 3-state pattern as RideDetailView)

    @ViewBuilder
    private func statsPanel() -> some View {
        VStack(spacing: 6) {
            if panelState != .collapsed {
                panelDragHandle()

                TabView(selection: $panelPage) {
                    combinedStatsPage().tag(0)
                    segmentStatsPage().tag(1)
                    chartsPage().tag(2)
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: panelState == .expanded ? 280 : 200)
                .scrollDisabled(scrubDistance != nil)

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
        .frame(maxWidth: .infinity, alignment: panelState != .collapsed ? .center : .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            if panelState == .collapsed {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    panelState = .compact
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
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            if value.translation.height > 0 {
                                switch panelState {
                                case .expanded: panelState = .compact
                                case .compact:  panelState = .collapsed
                                case .collapsed: break
                                }
                            } else {
                                switch panelState {
                                case .collapsed: panelState = .compact
                                case .compact:   panelState = .expanded
                                case .expanded:  break
                                }
                            }
                        }
                    }
            )
    }

    private func panelPageDots() -> some View {
        HStack(spacing: 6) {
            ForEach(0..<3, id: \.self) { i in
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

    // MARK: - Pages

    @ViewBuilder
    private func combinedStatsPage() -> some View {
        VStack(spacing: 8) {
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            let stats = combinedStats(compact: panelState == .compact)
            let rows = stats.chunked(into: 3)

            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if rowIdx > 0 { Divider() }
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(row, id: \.label) { stat in
                        MultiStatItem(label: stat.label, value: stat.value)
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
    private func segmentStatsPage() -> some View {
        let segs = renders.map(\.stat)
        VStack(spacing: 8) {
            let columns = [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
            LazyVGrid(columns: columns, spacing: 10) {
                MultiStatItem(label: "Segments", value: "\(segs.count)")
                MultiStatItem(label: "Avg Length", value: segs.isEmpty ? "—" : formatDistance(segs.map(\.distance).reduce(0, +) / Double(segs.count)))
                MultiStatItem(label: "Avg Time", value: segs.isEmpty ? "—" : formatTime(segs.map(\.movingTime).reduce(0, +) / Double(segs.count)))
            }
            Divider()
            LazyVGrid(columns: columns, spacing: 10) {
                MultiStatItem(label: "Avg Elev Gain", value: segs.isEmpty ? "—" : formatElevation(segs.map(\.elevationGain).reduce(0, +) / Double(segs.count)))
                MultiStatItem(label: "Longest", value: segs.map(\.distance).max().map { formatDistance($0) } ?? "—")
                MultiStatItem(label: "Shortest", value: segs.map(\.distance).min().map { formatDistance($0) } ?? "—")
            }

            if panelState == .expanded {
                Divider()
                ScrollView {
                    VStack(spacing: 6) {
                        ForEach(Array(segs.enumerated()), id: \.offset) { idx, s in
                            HStack(spacing: 8) {
                                Circle().fill(s.color).frame(width: 10, height: 10)
                                Text("\(idx + 1).")
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                                Text(s.name)
                                    .font(.caption)
                                    .lineLimit(1)
                                Spacer()
                                Text(formatDistance(s.distance))
                                    .font(.caption.monospacedDigit())
                                Text(formatTime(s.movingTime))
                                    .font(.caption.monospacedDigit())
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } else {
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        panelState = .expanded
                    }
                } label: {
                    HStack(spacing: 4) {
                        Text("More")
                            .font(.caption2.weight(.medium))
                        Image(systemName: "chevron.down")
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
            if !combinedChart.isEmpty {
                RideChartsView(
                    dataPoints: combinedChart,
                    hasHeartRate: chartHasHR,
                    hasPower: chartHasPower,
                    scrubDistance: $scrubDistance,
                    scrubColor: $scrubColor
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

    // MARK: - Stats math

    private var hasExtendedStats: Bool {
        rides.contains { r in
            r.maxSpeed != nil || r.avgPower != nil || r.maxPower != nil ||
            r.avgHeartRate != nil || r.maxHeartRate != nil ||
            r.highestElevation != nil || r.lowestElevation != nil || r.calories > 0
        }
    }

    private func combinedStats(compact: Bool) -> [(label: String, value: String)] {
        var stats: [(label: String, value: String)] = []
        let totalDistance = rides.map(\.distance).reduce(0, +)
        let totalMoving = rides.map(\.movingTime).reduce(0, +)
        let totalElapsed = rides.map(\.elapsedTime).reduce(0, +)
        let elevGain = rides.map(\.elevationGain).reduce(0, +)
        let elevLoss = rides.map(\.elevationLoss).reduce(0, +)
        let avgSpeed = totalMoving > 0 ? totalDistance / totalMoving : 0

        stats.append(("Distance", formatDistance(totalDistance)))
        stats.append(("Moving Time", formatTime(totalMoving)))
        stats.append(("Avg Speed", formatSpeed(avgSpeed)))
        stats.append(("Elapsed", formatTime(totalElapsed)))
        if let maxSpeed = rides.compactMap(\.maxSpeed).max() {
            stats.append(("Max Speed", formatSpeed(maxSpeed)))
        }

        if elevGain > 0 { stats.append(("Elev Gain", formatElevation(elevGain))) }
        if elevLoss > 0 { stats.append(("Elev Loss", formatElevation(elevLoss))) }
        if let high = rides.compactMap(\.highestElevation).max() {
            stats.append(("High Elev", formatElevation(high)))
        }
        if let low = rides.compactMap(\.lowestElevation).min() {
            stats.append(("Low Elev", formatElevation(low)))
        }

        guard !compact else { return stats }

        // Weighted-by-moving-time HR/power averages
        let hrSamples = rides.compactMap { r -> (Double, TimeInterval)? in
            guard let hr = r.avgHeartRate else { return nil }
            return (hr, r.movingTime)
        }
        if !hrSamples.isEmpty {
            let totW = hrSamples.map(\.1).reduce(0, +)
            if totW > 0 {
                let avg = hrSamples.map { $0.0 * $0.1 }.reduce(0, +) / totW
                stats.append(("Avg HR", "\(Int(avg.rounded())) bpm"))
            }
        }
        if let maxHR = rides.compactMap(\.maxHeartRate).max() {
            stats.append(("Max HR", "\(Int(maxHR.rounded())) bpm"))
        }

        let pwSamples = rides.compactMap { r -> (Double, TimeInterval)? in
            guard let pw = r.avgPower else { return nil }
            return (pw, r.movingTime)
        }
        if !pwSamples.isEmpty {
            let totW = pwSamples.map(\.1).reduce(0, +)
            if totW > 0 {
                let avg = pwSamples.map { $0.0 * $0.1 }.reduce(0, +) / totW
                stats.append(("Avg Power", "\(Int(avg.rounded())) W"))
            }
        }
        if let maxPw = rides.compactMap(\.maxPower).max() {
            stats.append(("Max Power", "\(Int(maxPw.rounded())) W"))
        }

        let totalCal = rides.map(\.calories).reduce(0, +)
        if totalCal > 0 { stats.append(("Calories", String(format: "%.0f kcal", totalCal))) }

        return stats
    }

    // MARK: - Cache build

    private func buildCache() {
        var built: [RideRender] = []
        var conns: [Connector] = []
        var chart: [ChartDataPoint] = []
        var distOffset: Double = 0
        var anyHR = false, anyPower = false

        for (idx, ride) in rides.enumerated() {
            let color = Self.segmentColors[idx % Self.segmentColors.count]
            let url = rideStore.trackURL(for: ride)
            guard let data = try? Data(contentsOf: url) else { continue }
            let pts = TrackEncoder.decode(data)
            let locations = TrackEncoder.toLocations(pts)
            guard locations.count >= 2 else { continue }

            let coords = locations.map(\.coordinate)
            let stat = SegmentStat(
                name: ride.name,
                distance: ride.distance,
                movingTime: ride.movingTime,
                elapsedTime: ride.elapsedTime,
                elevationGain: ride.elevationGain,
                avgSpeed: ride.avgSpeed,
                color: color
            )

            // Connector from previous render's end to this start
            if let prev = built.last,
               let prevEnd = prev.coords.last,
               let thisStart = coords.first {
                let gap = CLLocation(latitude: prevEnd.latitude, longitude: prevEnd.longitude)
                    .distance(from: CLLocation(latitude: thisStart.latitude, longitude: thisStart.longitude))
                if gap < Self.closeConnectorMeters {
                    // Extend the previous ride's color directly over to the next start.
                    conns.append(Connector(from: prevEnd, to: thisStart, color: prev.color, dashed: false))
                } else {
                    conns.append(Connector(from: prevEnd, to: thisStart, color: .gray, dashed: true))
                }
            }

            built.append(RideRender(id: ride.id, coords: coords, color: color, stat: stat))

            // Combined chart — append with running offset
            let (segPoints, hasHR, hasPower) = buildRideChartData(from: url)
            if hasHR { anyHR = true }
            if hasPower { anyPower = true }
            for pt in segPoints {
                chart.append(ChartDataPoint(
                    distance: pt.distance + distOffset,
                    elevation: pt.elevation,
                    speed: pt.speed,
                    heartRate: pt.heartRate,
                    power: pt.power))
            }
            if let last = segPoints.last { distOffset += last.distance }
        }

        renders = built
        connectors = conns
        combinedChart = chart
        chartHasHR = anyHR
        chartHasPower = anyPower

        // Fit camera to union of all coordinates
        if let region = fittingRegion(for: built.flatMap(\.coords)) {
            mapPosition = .region(region)
        }
    }

    private func fittingRegion(for coords: [CLLocationCoordinate2D]) -> MKCoordinateRegion? {
        guard !coords.isEmpty else { return nil }
        var minLat = coords[0].latitude, maxLat = coords[0].latitude
        var minLon = coords[0].longitude, maxLon = coords[0].longitude
        for c in coords {
            minLat = min(minLat, c.latitude); maxLat = max(maxLat, c.latitude)
            minLon = min(minLon, c.longitude); maxLon = max(maxLon, c.longitude)
        }
        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2)
        let span = MKCoordinateSpan(
            latitudeDelta: max(0.005, (maxLat - minLat) * 1.25),
            longitudeDelta: max(0.005, (maxLon - minLon) * 1.25))
        return MKCoordinateRegion(center: center, span: span)
    }
}

private struct MultiStatItem: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(value).font(.subheadline.weight(.semibold))
            Text(label).font(.caption2).foregroundStyle(.secondary)
        }
    }
}
