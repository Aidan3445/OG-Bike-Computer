
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
            if showFullRoute {
                FullRouteCanvas(workout: workout)
            } else {
                BreadcrumbCanvas(
                    workout: workout,
                    viewDistance: zoomLevels[zoomIndex])
            }

            // Controls overlay
            VStack {
                HStack {
                    Spacer()
                    Button {
                        showFullRoute.toggle()
                        if showFullRoute {
                            scheduleAutoSwitch()
                        } else {
                            autoSwitchTask?.cancel()
                        }
                    } label: {
                        Image(systemName: showFullRoute ? "scope" : "map")
                            .font(.system(size: 14, weight: .semibold))
                            .padding(6)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }

                Spacer()

                if !showFullRoute {
                    HStack {
                        Button {
                            zoomIndex = max(0, zoomIndex - 1)
                        } label: {
                            Image(systemName: "minus")
                                .font(.system(size: 12, weight: .bold))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(zoomIndex > 0 ? 1 : 0.3)

                        Spacer()

                        Button {
                            zoomIndex = min(zoomLevels.count - 1, zoomIndex + 1)
                        } label: {
                            Image(systemName: "plus")
                                .font(.system(size: 12, weight: .bold))
                                .padding(6)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                        .opacity(zoomIndex < zoomLevels.count - 1 ? 1 : 0.3)
                    }
                }
            }
            .padding(8)
        }
    }

    private func scheduleAutoSwitch() {
        autoSwitchTask?.cancel()
        autoSwitchTask = Task {
            try? await Task.sleep(for: .seconds(60))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                showFullRoute = false
            }
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

            let transform = makeTransform(route: processed, size: size, padding: 8)

            // Upcoming route (gray)
            var path = Path()
            let first = project(points[0].coordinate, transform: transform)
            path.move(to: first)
            for i in 1..<points.count {
                path.addLine(to: project(points[i].coordinate, transform: transform))
            }
            context.stroke(path, with: .color(.gray), lineWidth: 2)

            // Completed portion (green)
            let segIdx = workout.navigation.currentSegmentIndex
            if segIdx > 0 {
                var done = Path()
                done.move(to: first)
                for i in 1...min(segIdx, points.count - 1) {
                    done.addLine(to: project(points[i].coordinate, transform: transform))
                }
                context.stroke(done, with: .color(.green), lineWidth: 3)
            }

            // Current position dot
            if let loc = workout.currentLocation {
                let pos = project(loc.coordinate, transform: transform)
                context.fill(
                    Path(ellipseIn: CGRect(x: pos.x - 5, y: pos.y - 5, width: 10, height: 10)),
                    with: .color(.white))
                context.fill(
                    Path(ellipseIn: CGRect(x: pos.x - 3.5, y: pos.y - 3.5, width: 7, height: 7)),
                    with: .color(.blue))
            }
        }
    }

    private struct MapTransform {
        let offsetX: Double
        let offsetY: Double
        let scale: Double
        let cosLat: Double
    }

    private func makeTransform(route: ProcessedRoute, size: CGSize, padding: CGFloat) -> MapTransform {
        let centerLat = (route.minLat + route.maxLat) / 2
        let cosLat = cos(centerLat * .pi / 180)

        let latSpan = route.maxLat - route.minLat
        let lonSpan = (route.maxLon - route.minLon) * cosLat

        let drawW = Double(size.width - padding * 2)
        let drawH = Double(size.height - padding * 2)

        let scale: Double
        if latSpan == 0 && lonSpan == 0 {
            scale = 1
        } else {
            scale = min(drawW / lonSpan, drawH / latSpan)
        }

        let midLon = (route.minLon + route.maxLon) / 2
        let midLat = (route.minLat + route.maxLat) / 2

        return MapTransform(
            offsetX: Double(size.width) / 2 - midLon * cosLat * scale,
            offsetY: Double(size.height) / 2 + midLat * scale,
            scale: scale,
            cosLat: cosLat)
    }

    private func project(_ coord: CLLocationCoordinate2D, transform: MapTransform) -> CGPoint {
        let x = coord.longitude * transform.cosLat * transform.scale + transform.offsetX
        let y = -coord.latitude * transform.scale + transform.offsetY
        return CGPoint(x: x, y: y)
    }
}

private struct BreadcrumbCanvas: View {
    @ObservedObject var workout: WorkoutManager
    let viewDistance: Double

    private let routeLineWidth: CGFloat = 6
    private let completedLineWidth: CGFloat = 6

    var body: some View {
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

            let behind = viewDistance * 0.5
            let ahead = viewDistance * 1.5
            let minDist = currentDist - behind
            let maxDist = currentDist + ahead

            var windowPoints: [(coord: CLLocationCoordinate2D, dist: Double)] = []
            for point in points {
                if point.distanceFromStart >= minDist - 100 &&
                   point.distanceFromStart <= maxDist + 100 {
                    windowPoints.append((point.coordinate, point.distanceFromStart))
                }
            }

            guard windowPoints.count >= 2 else { return }

            let center = location.coordinate
            let metersPerPoint = Double(min(size.width, size.height)) / viewDistance
            let rotationRad = -bearing * .pi / 180
            let riderScreenY = size.height * 0.75
            let riderScreenX = size.width / 2

            func projectLocal(_ coord: CLLocationCoordinate2D) -> CGPoint {
                let cosLat = cos(center.latitude * .pi / 180)
                let dx = (coord.longitude - center.longitude) * cosLat * 111_320
                let dy = (coord.latitude - center.latitude) * 111_320

                let rx = dx * cos(rotationRad) - dy * sin(rotationRad)
                let ry = dx * sin(rotationRad) + dy * cos(rotationRad)

                return CGPoint(
                    x: riderScreenX + rx * metersPerPoint,
                    y: riderScreenY - ry * metersPerPoint)
            }

            var behindPath = Path()
            var aheadPath = Path()
            var startedBehind = false
            var startedAhead = false

            for wp in windowPoints {
                let pt = projectLocal(wp.coord)
                if wp.dist <= currentDist {
                    if !startedBehind {
                        behindPath.move(to: pt)
                        startedBehind = true
                    } else {
                        behindPath.addLine(to: pt)
                    }
                    if !startedAhead {
                        aheadPath.move(to: pt)
                    }
                } else {
                    if !startedAhead {
                        if !startedBehind {
                            aheadPath.move(to: pt)
                        } else {
                            aheadPath.addLine(to: pt)
                        }
                        startedAhead = true
                    } else {
                        aheadPath.addLine(to: pt)
                    }
                }
            }

            context.stroke(behindPath, with: .color(.green.opacity(0.4)),
                           style: StrokeStyle(lineWidth: completedLineWidth, lineCap: .round, lineJoin: .round))
            context.stroke(aheadPath, with: .color(.white),
                           style: StrokeStyle(lineWidth: routeLineWidth, lineCap: .round, lineJoin: .round))

            for turn in processed.turnPoints {
                if turn.distanceFromStart > minDist && turn.distanceFromStart < maxDist {
                    let pt = projectLocal(turn.coordinate)
                    let rect = CGRect(x: pt.x - 5, y: pt.y - 5, width: 10, height: 10)
                    context.fill(Path(ellipseIn: rect), with: .color(.yellow))
                }
            }

            let riderPt = CGPoint(x: riderScreenX, y: riderScreenY)
            context.fill(
                Path(ellipseIn: CGRect(x: riderPt.x - 8, y: riderPt.y - 8, width: 16, height: 16)),
                with: .color(.white))
            context.fill(
                Path(ellipseIn: CGRect(x: riderPt.x - 6, y: riderPt.y - 6, width: 12, height: 12)),
                with: .color(.blue))
        }
    }
}
