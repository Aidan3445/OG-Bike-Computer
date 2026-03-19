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
    @State private var showShareSheet = false
    @State private var segments: [SpeedPolyline] = []
    @State private var startCoord: CLLocationCoordinate2D?
    @State private var endCoord: CLLocationCoordinate2D?
    @State private var elevationExtremes: (high: ElevPoint, low: ElevPoint)?

    let buttonHeight: CGFloat = 44

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
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapCompass()
                MapScaleView()
            }

            // Floating stats bar — matches RouteDetailView
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    expanded.toggle()
                }
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "chevron.left")
                        .rotationEffect(expanded ? .zero : .degrees(180))
                        .font(.title3)
                        .foregroundStyle(.secondary)

                    if expanded {
                        VStack(spacing: 6) {
                            HStack(spacing: 0) {
                                StatItem(label: "Distance", value: formatDistance(ride.distance))
                                Spacer()
                                StatItem(label: "Time", value: formatTime(ride.movingTime))
                                Spacer()
                                StatItem(label: "Speed", value: formatSpeed(ride.avgSpeed))
                            }
                            if ride.elevationGain > 0 {
                                HStack(spacing: 0) {
                                    StatItem(label: "Gain", value: formatElevation(ride.elevationGain))
                                    Spacer()
                                    StatItem(label: "Loss", value: formatElevation(ride.elevationLoss))
                                }
                            }
                        }
                        .transition(.opacity.combined(with: .move(edge: .trailing)))
                    }
                }
                .padding(.horizontal, expanded ? 16 : 0)
                .frame(
                    width: expanded ? nil : buttonHeight,
                    height: buttonHeight,
                    alignment: .center)
                .clipped()
                .contentShape(Rectangle())
            }
            .padding(.bottom, 24)
            .padding(.trailing, 8)
            .frame(maxWidth: .infinity, alignment: .trailing)
            .buttonStyle(.borderedProminent)
            .buttonBorderShape(.capsule)
            .tint(.black.opacity(0.65))
            .shadow(color: .black.opacity(0.12), radius: 10, y: 3)
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
