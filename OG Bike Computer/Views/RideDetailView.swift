//
//  RideDetailView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import SwiftUI
import MapKit
import CoreLocation
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "RideDetail")

struct RideDetailView: View {
    let ride: RideSummary
    let rideStore: RideStore
    @ObservedObject private var unitState = UnitState.shared
    @ObservedObject private var uploadManager = UploadManager.shared

    init(ride: RideSummary, rideStore: RideStore) {
        self.ride = ride
        self.rideStore = rideStore
        logger.info("[RideDetail] init: ride=\(ride.id) '\(ride.name)' points=\(ride.pointCount) dist=\(ride.distance)")
    }

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showShareSheet = false
    @State private var isUploadingToStrava = false
    @State private var uploadError: String?
    @State private var segments: [SpeedPolyline] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    @State private var mileMarkers: [MileMarker] = []

    var body: some View {
        let _ = logger.info("[RideDetail] body: rendering for ride \(self.ride.id) '\(self.ride.name)'")
        let _ = logger.info("[RideDetail] body: segments=\(self.segments.count) start=\(self.startCoord != nil) end=\(self.endCoord != nil) elevExtremes=\(self.elevationExtremes != nil) markers=\(self.mileMarkers.count)")
        let _ = unitState.preferences
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                ForEach(segments) { seg in
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

                    let alreadyOnStrava = ride.uploads?.contains(where: { $0.service == .strava }) == true
                    if KeychainHelper.loadTokens(for: .strava) != nil && !alreadyOnStrava {
                        Button {
                            uploadToStrava()
                        } label: {
                            Label("Upload to Strava", systemImage: "figure.outdoor.cycle")
                        }
                        .disabled(isUploadingToStrava)
                    }

                    if let uploads = ride.uploads, !uploads.isEmpty {
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
        .onAppear { loadTrack() }
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

    private func loadTrack() {
        logger.info("[RideDetail] loadTrack: starting for ride \(ride.id)")
        let url = rideStore.trackURL(for: ride)
        logger.info("[RideDetail] loadTrack: trackURL = \(url.path)")
        guard let data = try? Data(contentsOf: url) else {
            logger.info("[RideDetail] loadTrack: failed to read track data from disk")
            return
        }
        logger.info("[RideDetail] loadTrack: read \(data.count) bytes")
        let points = TrackEncoder.decode(data)
        logger.info("[RideDetail] loadTrack: decoded \(points.count) track points")
        let locations = TrackEncoder.toLocations(points)
        logger.info("[RideDetail] loadTrack: converted to \(locations.count) CLLocations")
        guard locations.count >= 2 else {
            logger.info("[RideDetail] loadTrack: not enough locations (<2), bailing")
            return
        }

        startCoord = locations.first?.coordinate
        endCoord = locations.last?.coordinate
        logger.info("[RideDetail] loadTrack: set start/end coords")

        // Build cumulative distances and per-segment speeds
        let sampleInterval: Double = 30 // meters — speed is averaged over this window
        var cumDists: [Double] = [0]
        var rawSpeeds: [Double] = [] // one per segment (between consecutive points)
        for i in 1..<locations.count {
            let segDist = locations[i].distance(from: locations[i - 1])
            let dt = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)
            cumDists.append(cumDists.last! + segDist)
            rawSpeeds.append(dt > 0 ? segDist / dt : 0)
        }

        // Build speed samples at fixed intervals for smooth color curve
        let totalDist = cumDists.last ?? 0
        var speedSamples: [(dist: Double, speed: Double)] = []
        var windowStart = 0
        var sampleDist: Double = 0
        while sampleDist <= totalDist {
            // Average raw speeds of all segments within ±sampleInterval/2 of this distance
            let lo = sampleDist - sampleInterval / 2
            let hi = sampleDist + sampleInterval / 2
            var sum: Double = 0
            var count = 0
            for j in windowStart..<rawSpeeds.count {
                let segMid = (cumDists[j] + cumDists[j + 1]) / 2
                if segMid < lo { windowStart = j; continue }
                if segMid > hi { break }
                sum += rawSpeeds[j]
                count += 1
            }
            speedSamples.append((sampleDist, count > 0 ? sum / Double(count) : 0))
            sampleDist += sampleInterval
        }

        // Use percentile-based range so outliers don't wash out the colors
        let movingSpeeds = speedSamples.map(\.speed).filter { $0 > 0.5 }.sorted()
        let p10 = movingSpeeds.isEmpty ? 0.0 : movingSpeeds[movingSpeeds.count / 10]
        let p90 = movingSpeeds.isEmpty ? 1.0 : movingSpeeds[min(movingSpeeds.count - 1, movingSpeeds.count * 9 / 10)]
        let speedRange = max(p90 - p10, 0.1)
        logger.info("[RideDetail] loadTrack: \(speedSamples.count) speed samples, p10=\(p10) p90=\(p90)")

        // Interpolate smooth speed for each original GPS point from the sample curve
        func interpolatedSpeed(at dist: Double) -> Double {
            guard speedSamples.count >= 2 else { return speedSamples.first?.speed ?? 0 }
            // Binary search for the bracketing samples
            var lo = 0, hi = speedSamples.count - 1
            while lo < hi - 1 {
                let mid = (lo + hi) / 2
                if speedSamples[mid].dist <= dist { lo = mid } else { hi = mid }
            }
            let s0 = speedSamples[lo], s1 = speedSamples[hi]
            let gap = s1.dist - s0.dist
            guard gap > 0 else { return s0.speed }
            let t = max(0, min(1, (dist - s0.dist) / gap))
            return s0.speed + (s1.speed - s0.speed) * t
        }

        // Build colored segments using original GPS coordinates with smooth colors
        var segs: [SpeedPolyline] = []
        var batchCoords: [CLLocationCoordinate2D] = [locations[0].coordinate]
        var batchColor = speedColor(ratio: max(0, min(1, (interpolatedSpeed(at: 0) - p10) / speedRange)))

        for i in 1..<locations.count {
            let speed = interpolatedSpeed(at: cumDists[i])
            let ratio = max(0, min(1, (speed - p10) / speedRange))
            let color = speedColor(ratio: ratio)

            if color == batchColor {
                batchCoords.append(locations[i].coordinate)
            } else {
                batchCoords.append(locations[i].coordinate)
                segs.append(SpeedPolyline(coords: batchCoords, color: batchColor))
                batchCoords = [locations[i].coordinate]
                batchColor = color
            }
        }
        if batchCoords.count >= 2 {
            segs.append(SpeedPolyline(coords: batchCoords, color: batchColor))
        }
        segments = segs
        logger.info("[RideDetail] loadTrack: built \(segs.count) speed segments")

        // Mile markers
        mileMarkers = computeRideMileMarkers(locations: locations)
        logger.info("[RideDetail] loadTrack: computed \(mileMarkers.count) mile markers")

        // Elevation extremes
        let minElevDiff: Double = 50
        let withElev = locations.filter { $0.verticalAccuracy >= 0 }
        logger.info("[RideDetail] loadTrack: \(withElev.count) points with valid elevation")
        if let highest = withElev.max(by: { $0.altitude < $1.altitude }),
           let lowest = withElev.min(by: { $0.altitude < $1.altitude }),
           highest.altitude - lowest.altitude >= minElevDiff {
            elevationExtremes = (
                high: ElevPoint(coordinate: highest.coordinate, elevation: highest.altitude),
                low: ElevPoint(coordinate: lowest.coordinate, elevation: lowest.altitude))
            logger.info("[RideDetail] loadTrack: elevation extremes set (high=\(highest.altitude), low=\(lowest.altitude))")
        } else {
            logger.info("[RideDetail] loadTrack: no significant elevation extremes found")
        }
        logger.info("[RideDetail] loadTrack: done")
    }

    /// Red → yellow → green gradient. Lightly quantized (32 steps) so nearby
    /// colors batch into single polylines for performance while looking smooth.
    private func speedColor(ratio: Double) -> Color {
        let step = (ratio * 31).rounded() / 31
        let r: Double
        let g: Double
        if step < 0.5 {
            let t = step * 2
            r = 1.0
            g = t
        } else {
            let t = (step - 0.5) * 2
            r = 1.0 - t
            g = 1.0
        }
        return Color(red: r, green: g, blue: 0)
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

struct ElevPoint {
    let coordinate: CLLocationCoordinate2D
    let elevation: Double
}

struct SpeedPolyline: Identifiable {
    let id = UUID()
    let coords: [CLLocationCoordinate2D]
    let color: Color
}
