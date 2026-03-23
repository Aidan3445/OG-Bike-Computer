//
//  RouteDetailView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI
import MapKit
import CoreLocation

struct RouteDetailView: View {
    let route: Route
    let isOnWatch: Bool
    let isUploading: Bool
    let isUploadBlocked: Bool
    let onSend: () -> Void

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var expanded = true
    @State private var showOverwriteAlert = false

    var body: some View {
        ZStack(alignment: .bottom) {
            Map(position: $mapPosition) {
                // Route polyline
                MapPolyline(coordinates: coordinates)
                    .stroke(.blue, lineWidth: 4)

                // Start marker
                if let first = coordinates.first {
                    Annotation("Start", coordinate: first) {
                        Circle()
                            .fill(.green)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                // End marker
                if let last = coordinates.last {
                    Annotation("End", coordinate: last) {
                        Circle()
                            .fill(.red)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                    }
                }

                // Elevation markers
                if let peaks = elevationExtremes {
                    Annotation("", coordinate: peaks.high.coordinate) {
                        VStack(spacing: 2) {
                            Text(formatElevation(peaks.high.elevation!))
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
                            Text(formatElevation(peaks.low.elevation!))
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

                // Current location
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }

            // Stats overlay — panel collapses into the button
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    if expanded {
                        Capsule()
                            .fill(Color.white.opacity(0.3))
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)

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
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                        expanded.toggle()
                    }
                }
            }
        }
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    if isUploading || isUploadBlocked { return }
                    if isOnWatch {
                        showOverwriteAlert = true
                    } else {
                        onSend()
                    }
                } label: {
                    Group {
                        if isUploading {
                            ProgressView()
                        } else {
                            Image(systemName: isOnWatch ? "checkmark.circle.fill" : "arrow.up.circle")
                        }
                    }
                    .font(.title2)
                    .foregroundStyle(buttonColor(
                        isUploading: isUploading,
                        isUploadBlocked: isUploadBlocked,
                        isOnWatch: isOnWatch
                    ))
                }
                .disabled(isUploadBlocked)
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
    }
        
    private var coordinates: [CLLocationCoordinate2D] {
        route.points.map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lon)
        }
    }

    private var mileMarkers: [MileMarker] {
        // Convert route TrackPoints to ProcessedPoints for the shared utility
        let pts = route.points
        guard pts.count >= 2 else { return [] }
        var cumDist: Double = 0
        var processed: [ProcessedPoint] = []
        for i in 0..<pts.count {
            if i > 0 {
                let prev = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
                let cur = CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
                cumDist += cur.distance(from: prev)
            }
            processed.append(ProcessedPoint(
                coordinate: CLLocationCoordinate2D(latitude: pts[i].lat, longitude: pts[i].lon),
                elevation: pts[i].elevation,
                distanceFromStart: cumDist,
                bearingToNext: 0))
        }
        return computeMileMarkers(points: processed)
    }

    private let minElevDiff: Double = 50 // meters — minimum difference to show markers

    private var elevationExtremes: (high: TrackPoint, low: TrackPoint)? {
        let withElev = route.points.filter { $0.elevation != nil }
        guard let highest = withElev.max(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
              let lowest = withElev.min(by: { ($0.elevation ?? 0) < ($1.elevation ?? 0) }),
              let highElev = highest.elevation,
              let lowElev = lowest.elevation,
              highElev - lowElev >= minElevDiff else { return nil }
        return (highest, lowest)
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

