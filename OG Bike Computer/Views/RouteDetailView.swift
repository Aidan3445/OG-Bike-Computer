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
    let isQueued: Bool
    let isUploadBlocked: Bool
    let canSendToWatch: Bool
    let onSend: () -> Void
    @ObservedObject private var unitState = UnitState.shared

    enum PanelState {
        case collapsed, compact, expanded
    }

    @State private var mapPosition: MapCameraPosition = .automatic
    @State private var panelState: PanelState = .collapsed
    @State private var showOverwriteAlert = false

    // Cached derived data — computed once on appear to avoid O(n) work on every body recompute
    @State private var cachedCoordinates: [CLLocationCoordinate2D] = []
    @State private var cachedMileMarkers: [MileMarker] = []
    @State private var cachedElevationExtremes: (high: TrackPoint, low: TrackPoint)? = nil

    var body: some View {
        let _ = unitState.preferences
        ZStack(alignment: .bottom) {
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

                // Mile markers
                ForEach(Array(cachedMileMarkers.enumerated()), id: \.offset) { _, marker in
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

                // Current location
                UserAnnotation()
            }
            .mapStyle(.standard(elevation: .realistic))
            .mapControls {
                MapUserLocationButton()
                MapCompass()
                MapScaleView()
            }

            // Stats overlay — collapsed (button) ↔ compact (stats)
            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 12) {
                    if panelState != .collapsed {
                        Capsule()
                            .fill(.secondary)
                            .frame(width: 36, height: 4)
                            .padding(.top, 8)
                            .onTapGesture {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                                    panelState = .collapsed
                                }
                            }

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
        .navigationTitle(route.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
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
        .alert("Route Already on Watch", isPresented: $showOverwriteAlert) {
            Button("Replace", role: .destructive) {
                onSend()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(route.name)\" is already on your watch. Sending will replace the existing version.")
        }
        .onAppear { buildRouteCache() }
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

