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

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var expanded = true
    @State private var showAllStats = false
    @State private var showShareSheet = false
    @State private var segments: [SpeedPolyline] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?
    @State private var mileMarkers: [MileMarker] = []

    var body: some View {
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
                            Text("\(marker.mile) mi")
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

            // Stats overlay — panel collapses into the button
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    if expanded {
                        // Drag handle
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    expanded = false
                                }
                            }

                        let columns = [
                            GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())
                        ]

                        LazyVGrid(columns: columns, spacing: 10) {
                            StatItem(label: "Distance", value: formatDistance(ride.distance))
                            StatItem(label: "Moving Time", value: formatTime(ride.movingTime))
                            StatItem(label: "Avg Speed", value: formatSpeed(ride.avgSpeed))
                        }

                        if ride.elevationGain > 0 || ride.elevationLoss > 0 {
                            Divider().overlay(Color.white.opacity(0.15))
                            LazyVGrid(columns: columns, spacing: 10) {
                                StatItem(label: "Elev Gain", value: formatElevation(ride.elevationGain))
                                StatItem(label: "Elev Loss", value: formatElevation(ride.elevationLoss))
                                StatItem(label: "Elapsed", value: formatTime(ride.elapsedTime))
                            }
                        }

                        if showAllStats {
                            if ride.calories > 0 {
                                Divider().overlay(Color.white.opacity(0.15))
                                LazyVGrid(columns: columns, spacing: 10) {
                                    StatItem(label: "Calories", value: String(format: "%.0f kcal", ride.calories))
                                    StatItem(label: "Points", value: "\(ride.pointCount)")
                                    StatItem(label: "Activity", value: ride.activityType.rawValue.capitalized)
                                }
                            }

                            if hasExtendedStats {
                                Divider().overlay(Color.white.opacity(0.15))
                                LazyVGrid(columns: columns, spacing: 10) {
                                    if let maxSpd = ride.maxSpeed {
                                        StatItem(label: "Max Speed", value: formatSpeed(maxSpd))
                                    }
                                    if let avgPwr = ride.avgPower {
                                        StatItem(label: "Avg Power", value: "\(Int(avgPwr.rounded())) W")
                                    }
                                    if let maxPwr = ride.maxPower {
                                        StatItem(label: "Max Power", value: "\(Int(maxPwr.rounded())) W")
                                    }
                                }

                                if ride.avgHeartRate != nil || ride.highestElevation != nil {
                                    Divider().overlay(Color.white.opacity(0.15))
                                    LazyVGrid(columns: columns, spacing: 10) {
                                        if let avgHR = ride.avgHeartRate {
                                            StatItem(label: "Avg HR", value: "\(Int(avgHR.rounded())) bpm")
                                        }
                                        if let maxHR = ride.maxHeartRate {
                                            StatItem(label: "Max HR", value: "\(Int(maxHR.rounded())) bpm")
                                        }
                                        if let high = ride.highestElevation {
                                            StatItem(label: "High Elev", value: formatElevation(high))
                                        }
                                    }
                                }

                                if ride.lowestElevation != nil {
                                    Divider().overlay(Color.white.opacity(0.15))
                                    LazyVGrid(columns: columns, spacing: 10) {
                                        if let low = ride.lowestElevation {
                                            StatItem(label: "Low Elev", value: formatElevation(low))
                                        }
                                    }
                                }
                            }
                        }

                        // Show More / Show Less toggle
                        if hasExtendedStats || ride.calories > 0 {
                            Button {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                                    showAllStats.toggle()
                                }
                            } label: {
                                HStack(spacing: 4) {
                                    Text(showAllStats ? "Less" : "More")
                                        .font(.caption2.weight(.medium))
                                    Image(systemName: showAllStats ? "chevron.up" : "chevron.down")
                                        .font(.caption2)
                                }
                                .foregroundStyle(.secondary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else {
                        Image(systemName: "chart.bar.xaxis")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.top, 8)
                    }
                }
                .padding(.horizontal, expanded ? 16 : 0)
                .padding(.bottom, expanded ? 16 : 8)
                .frame(
                    maxWidth: expanded ? .infinity : nil,
                    alignment: expanded ? .center : .trailing
                )
                .frame(width: expanded ? nil : 48, height: expanded ? nil : 48)
                .background(
                    RoundedRectangle(cornerRadius: expanded ? 16 : 24)
                        .fill(Color.black.opacity(0.7))
                        .shadow(color: .black.opacity(0.25), radius: 12, y: 4)
                )
                .padding(.horizontal, expanded ? 12 : 0)
                .padding(.bottom, expanded ? 12 : 24)
                .padding(.trailing, expanded ? 0 : 16)
                .frame(maxWidth: .infinity, alignment: expanded ? .center : .trailing)
                .contentShape(Rectangle())
                .onTapGesture {
                    if !expanded {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                            expanded = true
                        }
                    }
                }
            }
        }
        .navigationTitle(ride.name)
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
            if let gpxURL = rideStore.exportGPX(for: ride) {
                ShareSheet(activityItems: [gpxURL])
            }
        }
        .onAppear { loadTrack() }
    }

    private var hasExtendedStats: Bool {
        ride.maxSpeed != nil || ride.avgPower != nil || ride.maxPower != nil ||
        ride.avgHeartRate != nil || ride.maxHeartRate != nil ||
        ride.highestElevation != nil || ride.lowestElevation != nil
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
