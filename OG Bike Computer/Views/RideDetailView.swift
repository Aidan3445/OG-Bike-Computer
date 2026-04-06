//
//  RideDetailView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct RideDetailView: View {
    let ride: RideSummary
    let rideStore: RideStore
    @ObservedObject private var unitState = UnitState.shared
    @ObservedObject private var uploadManager = UploadManager.shared

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showShareSheet = false
    @State private var isUploadingToStrava = false
    @State private var uploadError: String?
    @State private var coloredSegments: [ColoredSegment] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    @State private var mileMarkers: [MileMarker] = []

    var body: some View {
        let _ = unitState.preferences
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                ForEach(coloredSegments) { seg in
                    MapPolyline(coordinates: seg.coords)
                        .stroke(seg.color, lineWidth: 4)
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
                ForEach(Array(mileMarkers.enumerated()), id: \.offset) { _, marker in
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
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }

            // Stats overlay — 3 states: collapsed (button) → compact (core stats) → expanded (all stats)
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    if panelState != .collapsed {
                        // Drag handle — tap to collapse
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    panelState = .collapsed
                                }
                            }

                        let columns = [
                            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
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

                        // More / Less toggle — only show if there are extended stats
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
                    } else {
                        // Collapsed — single round button
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.primary)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, panelState != .collapsed ? 16 : 0)
                .padding(.bottom, panelState != .collapsed ? 16 : 8)
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
                            panelState = .compact
                        }
                    }
                }
                .gesture(
                    DragGesture(minimumDistance: 30)
                        .onEnded { value in
                            guard abs(value.translation.height) > 30,
                                  abs(value.translation.height) > abs(value.translation.width) else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                if value.translation.height > 0 {
                                    // Swipe down — collapse
                                    switch panelState {
                                    case .expanded: panelState = .compact
                                    case .compact: panelState = .collapsed
                                    case .collapsed: break
                                    }
                                } else {
                                    // Swipe up — expand
                                    switch panelState {
                                    case .collapsed: panelState = .compact
                                    case .compact: panelState = .expanded
                                    case .expanded: break
                                    }
                                }
                            }
                        }
                )
            }
        }
        .navigationTitle(ride.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        showShareSheet = true
                    } label: {
                        Label("Export GPX", systemImage: "square.and.arrow.up")
                    }

                    let alreadyOnStrava = ride.uploads?.contains(where: { $0.service == .strava && $0.isComplete }) == true
                    if KeychainHelper.loadTokens(for: .strava) != nil && !alreadyOnStrava {
                        Button {
                            uploadToStrava()
                        } label: {
                            Label("Upload to Strava", systemImage: "figure.outdoor.cycle")
                        }
                        .disabled(isUploadingToStrava)
                    }

                    if let uploads = ride.uploads?.filter({ $0.isComplete }), !uploads.isEmpty {
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
                    if isUploadingToStrava {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
            }
        }
        .sheet(isPresented: $showShareSheet) {
            if let gpxURL = rideStore.exportGPX(for: ride) {
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
            buildRideCache()
        }
    }

    private func uploadToStrava() {
        isUploadingToStrava = true
        Task {
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

    // MARK: - Track loading (synchronous, matches RouteDetailView pattern)

    private func buildRideCache() {
        let url = rideStore.trackURL(for: ride)
        guard let data = try? Data(contentsOf: url) else { return }
        let pts = TrackEncoder.decode(data)
        let locations = TrackEncoder.toLocations(pts)
        guard locations.count >= 2 else { return }

        startCoord        = locations.first?.coordinate
        endCoord          = locations.last?.coordinate
        mileMarkers       = computeRideMileMarkers(locations: locations)
        elevationExtremes = computeElevExtremes(locations: locations)
        coloredSegments   = buildColoredSegments(locations: locations, segmentCount: 500)
    }
}

// MARK: - Speed coloring

private struct ColoredSegment: Identifiable {
    let id = UUID()
    let coords: [CLLocationCoordinate2D]
    let color: Color
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
        return [ColoredSegment(coords: locations.map(\.coordinate), color: .blue)]
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
                color:  rideSpeedColor(ratio: Double(batchStep) / Double(colorSteps - 1))
            ))
            batchCoords = chunk.coords
            batchStep   = step
        }
    }
    if !batchCoords.isEmpty {
        segments.append(ColoredSegment(
            coords: batchCoords,
            color:  rideSpeedColor(ratio: Double(batchStep) / Double(colorSteps - 1))
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


