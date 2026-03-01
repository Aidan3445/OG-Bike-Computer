//
//  RouteMapView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI
import CoreLocation

struct RouteMapView: View {
    @ObservedObject var workout: WorkoutManager

    @State private var showFullRoute = false
    @State private var autoSwitchTask: Task<Void, Never>?

    private let zoomLevels: [Double] = [200, 400, 800, 1600]
    @State private var zoomIndex: Int = 1

    var body: some View {
        ZStack {
            Group {
                if showFullRoute {
                    FullRouteCanvas(workout: workout)
                } else {
                    BreadcrumbCanvas(
                        workout: workout,
                        viewDistance: zoomLevels[zoomIndex])
                }
            }
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    if !showFullRoute, let turn = workout.navigation.nextTurn,
                       !workout.navigation.isOffRoute {
                        VStack(spacing: 1) {
                            HStack(spacing: 4) {
                                Image(systemName: turn.direction.icon)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text(formatTurnDistance(workout.navigation.distanceToNextTurn))
                                    .font(.system(size: 12, weight: .semibold, design: .rounded))
                                    .monospacedDigit()
                            }
                            Text(formatDistance(workout.totalDistance))
                                .font(.system(size: 10, weight: .semibold, design: .rounded))
                            Text(formatTime(workout.movingTime))
                                .font(.system(size: 9))
                                .foregroundStyle(.secondary)
                        }
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.6))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }

                    Spacer()

                    VStack(spacing: 2) {
                        Button {
                            showFullRoute.toggle()
                            if showFullRoute {
                                scheduleAutoSwitch()
                            } else {
                                autoSwitchTask?.cancel()
                            }
                        } label: {
                            Image(systemName: showFullRoute ? "scope" : "map")
                                .font(.system(size: 13, weight: .semibold))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)

                        Text(cardinalDirection)
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(.white.opacity(0.7))
                    }
                }
                .padding(.horizontal, 4)
                .padding(.top, 0)

                Spacer()

                if !showFullRoute {
                    HStack(alignment: .bottom) {
                        Button {
                            if zoomIndex < zoomLevels.count - 1 {
                                zoomIndex += 1
                            }
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(zoomIndex < zoomLevels.count - 1 ? 1 : 0.3)

                        Spacer()

                        Button {
                            if zoomIndex > 0 {
                                zoomIndex -= 1
                            }
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 16, weight: .bold))
                                .frame(width: 36, height: 36)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(zoomIndex > 0 ? 1 : 0.3)
                    }
                    .padding(.horizontal, 4)
                    .padding(.bottom, 0)
                }
            }
        }
    }

    private var cardinalDirection: String {
        let heading: Double
        if workout.speed > 1.0, let course = workout.currentLocation?.course, course >= 0 {
            heading = course
        } else {
            heading = workout.heading
        }
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let index = Int(((heading + 22.5).truncatingRemainder(dividingBy: 360)) / 45)
        return dirs[max(0, min(index, dirs.count - 1))]
    }

    private func scheduleAutoSwitch() {
        autoSwitchTask?.cancel()
        autoSwitchTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await MainActor.run { showFullRoute = false }
        }
    }
}

private struct FullRouteCanvas: View {
    @ObservedObject var workout: WorkoutManager

    var body: some View {
        Canvas { context, size in
            guard let processed = workout.navigation.processedRoute else { return }
            let points = processed.points
            guard points.count >= 2 else { return }

            let transform = makeTransform(route: processed, size: size, padding: 12)
            let stride = max(1, points.count / 500)

            var path = Path()
            path.move(to: project(points[0].coordinate, transform: transform))
            for i in Swift.stride(from: 1, to: points.count, by: stride) {
                path.addLine(to: project(points[i].coordinate, transform: transform))
            }
            path.addLine(to: project(points[points.count - 1].coordinate, transform: transform))
            context.stroke(path, with: .color(.gray),
                           style: StrokeStyle(lineWidth: 2, lineCap: .round, lineJoin: .round))

            let segIdx = workout.navigation.currentSegmentIndex
            if segIdx > 0 {
                var done = Path()
                done.move(to: project(points[0].coordinate, transform: transform))
                let doneStride = max(1, segIdx / 300)
                for i in Swift.stride(from: 1, through: min(segIdx, points.count - 1), by: doneStride) {
                    done.addLine(to: project(points[i].coordinate, transform: transform))
                }
                done.addLine(to: project(points[min(segIdx, points.count - 1)].coordinate, transform: transform))
                context.stroke(done, with: .color(.green),
                               style: StrokeStyle(lineWidth: 3, lineCap: .round, lineJoin: .round))
            }

            if let loc = workout.currentLocation {
                let pos = project(loc.coordinate, transform: transform)
                context.fill(Path(ellipseIn: CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)), with: .color(.white))
                context.fill(Path(ellipseIn: CGRect(x: pos.x - 3.5, y: pos.y - 3.5, width: 7, height: 7)), with: .color(.blue))
            }
        }
    }

    private struct MapTransform {
        let offsetX: Double, offsetY: Double, scale: Double, cosLat: Double
    }

    private func makeTransform(route: ProcessedRoute, size: CGSize, padding: CGFloat) -> MapTransform {
        let centerLat = (route.minLat + route.maxLat) / 2
        let cosLat = cos(centerLat * .pi / 180)
        let latSpan = route.maxLat - route.minLat
        let lonSpan = (route.maxLon - route.minLon) * cosLat
        let drawW = Double(size.width - padding * 2)
        let drawH = Double(size.height - padding * 2)
        let scale = (latSpan == 0 && lonSpan == 0) ? 1 : min(drawW / lonSpan, drawH / latSpan)
        let midLon = (route.minLon + route.maxLon) / 2
        let midLat = (route.minLat + route.maxLat) / 2
        return MapTransform(
            offsetX: Double(size.width) / 2 - midLon * cosLat * scale,
            offsetY: Double(size.height) / 2 + midLat * scale,
            scale: scale, cosLat: cosLat)
    }

    private func project(_ coord: CLLocationCoordinate2D, transform: MapTransform) -> CGPoint {
        CGPoint(
            x: coord.longitude * transform.cosLat * transform.scale + transform.offsetX,
            y: -coord.latitude * transform.scale + transform.offsetY)
    }
}

private struct BreadcrumbCanvas: View {
    @ObservedObject var workout: WorkoutManager
    let viewDistance: Double

    private let routeLineWidth: CGFloat = 6

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.1)) { timeline in
            Canvas { context, size in
                guard let processed = workout.navigation.processedRoute,
                      let location = workout.currentLocation else { return }

                let points = processed.points
                let segIdx = workout.navigation.currentSegmentIndex
                guard points.count >= 2, segIdx < points.count else { return }

                let currentDist = workout.navigation.distanceAlongRoute

                let bearing: Double
                if workout.speed > 1.0, location.course >= 0 {
                    bearing = location.course
                } else if workout.heading > 0 {
                    bearing = workout.heading
                } else {
                    bearing = processed.points[segIdx].bearingToNext
                }

                let riderScreenX = size.width / 2
                let riderScreenY = size.height * 0.75
                let metersPerPx = min(size.width, size.height) / viewDistance

                let behind = viewDistance * 0.5
                let ahead = viewDistance * 1.5
                let minDist = currentDist - behind
                let maxDist = currentDist + ahead

                let center = location.coordinate
                let cosLat = cos(center.latitude * .pi / 180)
                let rotRad = bearing * .pi / 180

                var behindPath = Path()
                var aheadPath = Path()
                var startedBehind = false
                var startedAhead = false
                var lastSX: Double = .greatestFiniteMagnitude
                var lastSY: Double = .greatestFiniteMagnitude

                var bridgePoint: CGPoint?

                for point in points {
                    guard point.distanceFromStart >= minDist - 100,
                          point.distanceFromStart <= maxDist + 100 else { continue }

                    let dx = (point.coordinate.longitude - center.longitude) * cosLat * 111_320
                    let dy = (point.coordinate.latitude - center.latitude) * 111_320
                    let rx = dx * cos(rotRad) - dy * sin(rotRad)
                    let ry = dx * sin(rotRad) + dy * cos(rotRad)
                    let sx = riderScreenX + rx * metersPerPx
                    let sy = riderScreenY - ry * metersPerPx

                    if abs(sx - lastSX) + abs(sy - lastSY) < 2 { continue }
                    lastSX = sx
                    lastSY = sy

                    let pt = CGPoint(x: sx, y: sy)

                    if point.distanceFromStart <= currentDist {
                        if !startedBehind {
                            behindPath.move(to: pt)
                            startedBehind = true
                        } else {
                            behindPath.addLine(to: pt)
                        }
                        bridgePoint = pt
                    } else {
                        if !startedAhead {
                            if let bp = bridgePoint {
                                aheadPath.move(to: bp)
                                aheadPath.addLine(to: pt)
                            } else {
                                aheadPath.move(to: pt)
                            }
                            startedAhead = true
                        } else {
                            aheadPath.addLine(to: pt)
                        }
                    }
                }

                let style = StrokeStyle(lineWidth: routeLineWidth, lineCap: .round, lineJoin: .round)
                context.stroke(behindPath, with: .color(.green.opacity(0.4)), style: style)
                context.stroke(aheadPath, with: .color(.white), style: style)

                context.fill(
                    Path(ellipseIn: CGRect(x: riderScreenX - 8, y: riderScreenY - 8, width: 16, height: 16)),
                    with: .color(.white))
                context.fill(
                    Path(ellipseIn: CGRect(x: riderScreenX - 6, y: riderScreenY - 6, width: 12, height: 12)),
                    with: .color(.blue))
            }
        }
    }
}
