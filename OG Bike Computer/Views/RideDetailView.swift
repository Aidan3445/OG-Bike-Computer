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
    @State private var panelState: PanelState = .compact
    @State private var showShareSheet = false
    @State private var isUploadingToStrava = false
    @State private var uploadError: String?
    @State private var segments: [SpeedPolyline] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    @State private var mileMarkers: [MileMarker] = []

    var body: some View {
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
                        VStack(spacing: 1) {
                            Text("\(marker.mile) \(currentUnits.distance.label)")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 4)
                                .padding(.vertical, 1)
                                .background(.orange)
                                .clipShape(Capsule())
                            Image(systemName: "flag.fill")
                                .font(.system(size: 8))
                                .foregroundStyle(.orange)
                        }
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
                            .fill(Color.white.opacity(0.3))
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
                                Divider().overlay(Color.white.opacity(0.15))
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
                            .foregroundStyle(.white)
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
                        .fill(Color.black.opacity(0.7))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
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
                            guard value.translation.height > 30,
                                  abs(value.translation.height) > abs(value.translation.width) else { return }
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                switch panelState {
                                case .expanded: panelState = .compact
                                case .compact: panelState = .collapsed
                                case .collapsed: break
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

                    let stravaTokenExists = KeychainHelper.loadTokens(for: .strava) != nil
                    let alreadyOnStrava = ride.uploads?.contains(where: { $0.service == .strava }) == true
                    if stravaTokenExists && !alreadyOnStrava {
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
        let url = rideStore.trackURL(for: ride)
        guard let data = try? Data(contentsOf: url) else { return }
        let points = TrackEncoder.decode(data)
        let locations = TrackEncoder.toLocations(points)
        guard locations.count >= 2 else { return }

        startCoord = locations.first?.coordinate
        endCoord = locations.last?.coordinate

        // Compute speeds between consecutive points
        var speeds: [Double] = []
        for i in 1..<locations.count {
            let dist = locations[i].distance(from: locations[i - 1])
            let dt = locations[i].timestamp.timeIntervalSince(locations[i - 1].timestamp)
            speeds.append(dt > 0 ? dist / dt : 0)
        }

        let movingSpeeds = speeds.filter { $0 > 0.5 }
        let minSpeed = movingSpeeds.min() ?? 0
        let maxSpeed = movingSpeeds.max() ?? 1
        let range = max(maxSpeed - minSpeed, 0.1)

        // Build colored segments — batch consecutive similar colors
        var segs: [SpeedPolyline] = []
        var batchCoords: [CLLocationCoordinate2D] = [locations[0].coordinate]
        var batchColor = speedColor(ratio: 0)

        for i in 1..<locations.count {
            let ratio = max(0, min(1, (speeds[i - 1] - minSpeed) / range))
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

        // Mile markers
        mileMarkers = computeRideMileMarkers(locations: locations)

        // Elevation extremes
        let minElevDiff: Double = 50
        let withElev = locations.filter { $0.verticalAccuracy >= 0 }
        if let highest = withElev.max(by: { $0.altitude < $1.altitude }),
           let lowest = withElev.min(by: { $0.altitude < $1.altitude }),
           highest.altitude - lowest.altitude >= minElevDiff {
            elevationExtremes = (
                high: ElevPoint(coordinate: highest.coordinate, elevation: highest.altitude),
                low: ElevPoint(coordinate: lowest.coordinate, elevation: lowest.altitude))
        }
    }

    // Quantized to 8 steps so consecutive segments batch together
    private func speedColor(ratio: Double) -> Color {
        let step = (ratio * 7).rounded() / 7
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
