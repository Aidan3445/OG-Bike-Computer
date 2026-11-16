//
//  RideCharts.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/10/26.
//

import Charts
import Combine
import CoreLocation
import MapKit
import SwiftUI
import UIKit

// MARK: - Scrub State

/// Scrub position shared between a chart and its map. Written per drag frame
/// by the chart's gesture, observed only by the small leaf views that render
/// scrub UI (rule line, footer readout, map dot) — the chart body and the
/// map content never subscribe, so scrubbing can't trigger chart rebuilds or
/// map re-renders.
final class ChartScrubState: ObservableObject {
    /// Meters from start; nil when not scrubbing.
    @Published var distance: Double? = nil
    /// Color of the active chart metric, mirrored by the map dot.
    @Published var color: Color = .green
    /// Stretch between two pinching fingers, in meters. Live while pinching,
    /// nil otherwise. On release the chart zooms to it.
    @Published var pinch: ClosedRange<Double>? = nil
}

/// Shaded band between the pinching fingers, drawn in the chart's overlay so
/// per-frame pinch updates re-render only this view.
struct ChartPinchBand: View {
    @ObservedObject var scrub: ChartScrubState
    let proxy: ChartProxy
    let plotFrame: CGRect
    let metersPerUnit: Double

    var body: some View {
        if let range = scrub.pinch,
            let x1 = proxy.position(forX: range.lowerBound / metersPerUnit),
            let x2 = proxy.position(forX: range.upperBound / metersPerUnit)
        {
            let minX = plotFrame.minX + max(0, min(x1, x2))
            let maxX = plotFrame.minX + min(plotFrame.width, max(x1, x2))
            ZStack(alignment: .topLeading) {
                Rectangle()
                    .fill(scrub.color.opacity(0.15))
                    .frame(width: max(0, maxX - minX), height: plotFrame.height)
                    .offset(x: minX, y: plotFrame.minY)
                ForEach([minX, maxX], id: \.self) { x in
                    Rectangle()
                        .fill(scrub.color)
                        .frame(width: 2, height: plotFrame.height)
                        .offset(x: x - 1, y: plotFrame.minY)
                }
            }
            .allowsHitTesting(false)
        }
    }
}

/// Dashed vertical scrub line drawn in the chart's overlay (not as a chart
/// RuleMark) so per-frame scrub updates re-render only this path.
struct ChartScrubRule: View {
    @ObservedObject var scrub: ChartScrubState
    let proxy: ChartProxy
    let plotFrame: CGRect
    let metersPerUnit: Double

    var body: some View {
        if let dist = scrub.distance,
            let x = proxy.position(forX: dist / metersPerUnit)
        {
            Path { p in
                p.move(to: CGPoint(x: plotFrame.minX + x, y: plotFrame.minY))
                p.addLine(to: CGPoint(x: plotFrame.minX + x, y: plotFrame.maxY))
            }
            .stroke(scrub.color.opacity(0.8), style: StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            .allowsHitTesting(false)
        }
    }
}

/// Screen-space scrub dot layered over the map (not a map Annotation) so
/// moving it never touches the map's content. `coordinateFor` maps the scrub
/// distance to a track coordinate. While pinching a chart it shows A and B at
/// the two fingers' spots instead.
struct MapScrubDot: View {
    @ObservedObject var scrub: ChartScrubState
    let proxy: MapProxy
    let coordinateFor: (Double) -> CLLocationCoordinate2D?

    var body: some View {
        ZStack {
            if let range = scrub.pinch {
                ForEach([("A", range.lowerBound), ("B", range.upperBound)], id: \.0) { letter, distance in
                    if let coord = coordinateFor(distance),
                        let point = proxy.convert(coord, to: .local)
                    {
                        Text(letter)
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.white)
                            .frame(width: 20, height: 20)
                            .background(Circle().fill(scrub.color))
                            .overlay(Circle().stroke(.white, lineWidth: 2))
                            .shadow(radius: 3)
                            .position(point)
                    }
                }
            } else if let dist = scrub.distance,
                let coord = coordinateFor(dist),
                let point = proxy.convert(coord, to: .local)
            {
                Circle()
                    .fill(.white)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(scrub.color, lineWidth: 3))
                    .shadow(radius: 3)
                    .position(point)
            }
        }
        .allowsHitTesting(false)
    }
}

// MARK: - Long-Press-To-Scrub Recognizer
//
// SwiftUI's gesture system claims touches too eagerly to coexist cleanly with a
// `TabView(.page)` parent — even with `simultaneousGesture`, swipes between tab
// pages get swallowed. Bridging to a UIKit `UILongPressGestureRecognizer` with
// `cancelsTouchesInView = false` lets normal swipes pass through to the parent
// pager while still triggering scrub mode after a 0.25s hold.

struct LongPressScrubOverlay: UIViewRepresentable {
    var minimumDuration: TimeInterval = 0.25
    var allowableMovement: CGFloat = 12
    var onBegan: (CGPoint) -> Void
    var onChanged: (CGPoint) -> Void
    var onEnded: () -> Void
    /// The two fingers' x positions while pinching, left to right.
    var onPinchChanged: ((CGFloat, CGFloat) -> Void)? = nil
    var onPinchEnded: (() -> Void)? = nil

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:)))
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = .greatestFiniteMagnitude  // don't cancel once activated
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator

        context.coordinator.view = view
        context.coordinator.recognizer = recognizer
        view.addGestureRecognizer(recognizer)

        let pinch = UIPinchGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handlePinch(_:)))
        pinch.cancelsTouchesInView = false
        pinch.delegate = context.coordinator
        view.addGestureRecognizer(pinch)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
        context.coordinator.onPinchChanged = onPinchChanged
        context.coordinator.onPinchEnded = onPinchEnded
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onBegan: onBegan, onChanged: onChanged, onEnded: onEnded)
    }

    final class Coordinator: NSObject, UIGestureRecognizerDelegate {
        weak var view: UIView?
        weak var recognizer: UILongPressGestureRecognizer?
        /// All UIScrollView ancestors we disabled on `.began` so we can re-enable on `.ended`.
        private var lockedScrollViews: [UIScrollView] = []
        /// Other ancestor pan recognizers we briefly toggle on `.began` to cancel any
        /// gesture they had already started recognizing (e.g. NavigationStack swipe-back).
        private var bumpedPanRecognizers: [UIPanGestureRecognizer] = []
        var onBegan: (CGPoint) -> Void
        var onChanged: (CGPoint) -> Void
        var onEnded: () -> Void
        var onPinchChanged: ((CGFloat, CGFloat) -> Void)?
        var onPinchEnded: (() -> Void)?

        init(
            onBegan: @escaping (CGPoint) -> Void,
            onChanged: @escaping (CGPoint) -> Void,
            onEnded: @escaping () -> Void
        ) {
            self.onBegan = onBegan
            self.onChanged = onChanged
            self.onEnded = onEnded
        }

        @objc func handle(_ gr: UILongPressGestureRecognizer) {
            guard let view = view else { return }
            let loc = gr.location(in: view)
            switch gr.state {
            case .began:
                lockAncestorGestures(from: view)
                onBegan(loc)
            case .changed:
                onChanged(loc)
            case .ended, .cancelled, .failed:
                unlockAncestorGestures()
                onEnded()
            default:
                break
            }
        }

        @objc func handlePinch(_ gr: UIPinchGestureRecognizer) {
            guard let view, onPinchChanged != nil else { return }
            switch gr.state {
            case .began, .changed:
                if gr.state == .began { lockAncestorGestures(from: view) }
                // A finger can lift for a moment mid-pinch; skip those frames.
                guard gr.numberOfTouches >= 2 else { return }
                let a = gr.location(ofTouch: 0, in: view).x
                let b = gr.location(ofTouch: 1, in: view).x
                onPinchChanged?(min(a, b), max(a, b))
            case .ended, .cancelled, .failed:
                unlockAncestorGestures()
                onPinchEnded?()
            default:
                break
            }
        }

        /// Walk the superview chain and:
        ///   * Disable every UIScrollView (cancels any in-flight scroll)
        ///   * Toggle isEnabled on every UIPanGestureRecognizer to cancel any in-flight
        ///     pan (e.g. the navigation stack's interactive pop gesture)
        private func lockAncestorGestures(from view: UIView) {
            var current: UIView? = view.superview
            while let v = current {
                if let scroll = v as? UIScrollView, scroll.isScrollEnabled {
                    scroll.isScrollEnabled = false
                    lockedScrollViews.append(scroll)
                }
                if let recognizers = v.gestureRecognizers {
                    for r in recognizers where r is UIPanGestureRecognizer && r.isEnabled {
                        // Skip the page TabView's internal pan — already neutralized by
                        // disabling its scroll view above.
                        if let pan = r as? UIPanGestureRecognizer {
                            pan.isEnabled = false
                            pan.isEnabled = true
                            // Mark "bumped" only if it's NOT the scroll view's own pan
                            // (those re-enable cleanly when isScrollEnabled flips back).
                            if !(v is UIScrollView) {
                                bumpedPanRecognizers.append(pan)
                            }
                        }
                    }
                }
                current = v.superview
            }
        }

        private func unlockAncestorGestures() {
            for scroll in lockedScrollViews {
                scroll.isScrollEnabled = true
            }
            lockedScrollViews.removeAll()
            // Bumped pan recognizers were already re-enabled — just clear the list.
            bumpedPanRecognizers.removeAll()
        }

        // Allow other recognizers (parent TabView's pan, etc.) to recognize alongside us
        // BEFORE our long press fires — that's how normal swipes pass through. Once
        // `.began` fires we forcibly cancel them via `lockAncestorGestures`.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer
        ) -> Bool {
            true
        }

        // Reserve the leading edge for the NavigationStack swipe-back gesture —
        // touches that start within 40pt of the left edge never arm the scrubber.
        func gestureRecognizer(
            _ gestureRecognizer: UIGestureRecognizer,
            shouldReceive touch: UITouch
        ) -> Bool {
            guard let view = view else { return true }
            let x = touch.location(in: view).x
            return x >= 40
        }
    }
}

// MARK: - Data Model

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let distance: Double  // meters from start
    let elevation: Double  // meters
    let speed: Double  // m/s
    let heartRate: Double  // bpm (0 = no data)
    let power: Double  // watts (0 = no data)
    let grade: Double  // percent
    /// Seconds since the ride started, for the zoom readout. nil where time
    /// doesn't mean anything, like a combined multi-ride chart.
    var time: Double? = nil
}

// MARK: - Zoom

/// Smallest stretch a pinch can zoom to, so axis labels stay distinct.
let chartMinimumZoomSpan: Double = 300

/// Points to draw for `domain`: the ones inside it plus one either side so
/// the line reaches the edges, thinned to about `limit` so a zoomed-out
/// chart of a long ride stays cheap.
func chartPoints<T>(_ points: [T], distance: (T) -> Double, in domain: ClosedRange<Double>, limit: Int = 300) -> [T] {
    guard let first = points.firstIndex(where: { distance($0) >= domain.lowerBound }) else { return Array(points.suffix(1)) }
    let last = points.lastIndex(where: { distance($0) <= domain.upperBound }) ?? first
    let lo = max(0, first - 1)
    let hi = min(points.count - 1, max(last, first) + 1)
    let slice = Array(points[lo...hi])
    guard slice.count > limit else { return slice }
    let step = Double(slice.count - 1) / Double(limit - 1)
    return (0..<limit).map { slice[Int((Double($0) * step).rounded())] }
}

/// Gain and loss with a 2 m dead band, so GPS wobble on a flat stretch
/// doesn't add up to phantom climbing.
func chartGainLoss(_ elevations: [Double]) -> (gain: Double, loss: Double) {
    guard var reference = elevations.first else { return (0, 0) }
    var gain = 0.0, loss = 0.0
    for elevation in elevations.dropFirst() {
        if elevation - reference >= 2 {
            gain += elevation - reference
            reference = elevation
        } else if reference - elevation >= 2 {
            loss += reference - elevation
            reference = elevation
        }
    }
    return (gain, loss)
}

/// One line under a zoomed chart: what the stretch covers, and an X to zoom
/// back out.
struct ChartZoomReadout: View {
    let text: String
    let color: Color
    let onClear: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "plus.magnifyingglass")
                .font(.caption2)
                .foregroundStyle(color)
            Text(text)
                .font(.caption2.weight(.medium).monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Button(action: onClear) {
                Image(systemName: "xmark.circle.fill")
                    .font(.body)
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Zoom out")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(color.opacity(0.1), in: Capsule())
    }
}

/// Turns two finger x positions in the plot into a distance range.
func chartPinchRange(
    _ x1: CGFloat, _ x2: CGFloat, proxy: ChartProxy, plotFrame: CGRect,
    metersPerUnit: Double, domain: ClosedRange<Double>
) -> ClosedRange<Double>? {
    guard let a: Double = proxy.value(atX: x1 - plotFrame.minX),
          let b: Double = proxy.value(atX: x2 - plotFrame.minX) else { return nil }
    let lo = max(domain.lowerBound, min(a, b) * metersPerUnit)
    let hi = min(domain.upperBound, max(a, b) * metersPerUnit)
    return hi > lo ? lo...hi : nil
}

/// One colored run of the grade band under an elevation chart, in meters.
struct GradeBandSegment {
    let start: Double
    let end: Double
    let color: Color
}

/// Merges neighboring points of the same grade color so the band is a
/// handful of marks instead of one per chart point.
func gradeBand(distances: [Double], grades: [Double]) -> [GradeBandSegment] {
    guard distances.count >= 2, distances.count == grades.count else { return [] }
    var segments: [GradeBandSegment] = []
    for i in 1..<distances.count {
        let color = gradeColor(grades[i])
        if let last = segments.last, last.color == color {
            segments[segments.count - 1] = GradeBandSegment(
                start: last.start, end: distances[i], color: color)
        } else {
            segments.append(
                GradeBandSegment(start: distances[i - 1], end: distances[i], color: color))
        }
    }
    return segments
}

/// Elevation by distance, for reading grade off a profile at any spacing.
struct GradeProfile {
    private let distances: [Double]
    private let elevations: [Double]

    /// `points` must be in distance order. A 5 point median runs first so one
    /// bad fix can't spike the grade.
    init(_ points: [(distance: Double, elevation: Double)]) {
        distances = points.map(\.distance)
        let raw = points.map(\.elevation)
        elevations = raw.indices.map { i in
            let window = raw[max(0, i - 2)...min(raw.count - 1, i + 2)].sorted()
            return window[window.count / 2]
        }
    }

    /// Percent grade over ±`halfWindow` meters around `distance`, clamped to ±25%.
    func grade(at distance: Double, halfWindow: Double) -> Double {
        guard let first = distances.first, let last = distances.last, distances.count >= 2 else {
            return 0
        }
        let lo = max(first, distance - halfWindow)
        let hi = min(last, distance + halfWindow)
        guard hi - lo > 1 else { return 0 }
        let pct = (elevation(at: hi) - elevation(at: lo)) / (hi - lo) * 100
        return max(-25, min(25, pct))
    }

    private func elevation(at d: Double) -> Double {
        var lo = 0
        var hi = distances.count - 1
        while hi - lo > 1 {
            let mid = (lo + hi) / 2
            if distances[mid] <= d { lo = mid } else { hi = mid }
        }
        let span = distances[hi] - distances[lo]
        guard span > 0 else { return elevations[lo] }
        let t = max(0, min(1, (d - distances[lo]) / span))
        return elevations[lo] + (elevations[hi] - elevations[lo]) * t
    }
}

// MARK: - Ride Charts (multi-metric with toggles)

enum RideChartMetric: String, CaseIterable {
    case elevation, speed, heartRate, power

    var label: String {
        switch self {
        case .elevation: return "Elev"
        case .speed: return "Speed"
        case .heartRate: return "HR"
        case .power: return "Power"
        }
    }

    var color: Color {
        switch self {
        case .elevation: return .green
        case .speed: return .blue
        case .heartRate: return .red
        case .power: return .orange
        }
    }
}

/// Where one ride ends and the next begins on a combined chart.
struct ChartSplit {
    let distance: Double  // meters from start
    let color: Color  // the ride that starts here
}

struct RideChartsView: View {
    let dataPoints: [ChartDataPoint]
    let hasHeartRate: Bool
    let hasPower: Bool
    /// Deliberately NOT @ObservedObject — this view only writes to it from
    /// the gesture; the scrub-rendering leaf views observe it.
    let scrub: ChartScrubState
    var splits: [ChartSplit] = []
    /// The stretch the chart is zoomed to, in meters. A pinch sets it on
    /// release and the readout's X clears it. Owned by the screen so the map
    /// can highlight the same stretch.
    var zoom: Binding<ClosedRange<Double>?> = .constant(nil)

    @State private var selected: RideChartMetric = .elevation
    @State private var scrubActive = false
    @ObservedObject private var unitState = UnitState.shared
    @AppStorage(PhoneSettingsKeys.gradeColors) private var showGradeColors = true

    private var availableMetrics: [RideChartMetric] {
        var metrics: [RideChartMetric] = [.elevation, .speed]
        if hasHeartRate { metrics.append(.heartRate) }
        if hasPower { metrics.append(.power) }
        return metrics
    }

    private var fullDomain: ClosedRange<Double> {
        0...max(dataPoints.last?.distance ?? 0, 1)
    }

    private var domain: ClosedRange<Double> {
        zoom.wrappedValue ?? fullDomain
    }

    var body: some View {
        let _ = unitState.preferences
        let shown = chartPoints(dataPoints, distance: \.distance, in: domain)
        VStack(spacing: 8) {
            if let range = zoom.wrappedValue {
                ChartZoomReadout(text: zoomSummary(range), color: selected.color) {
                    withAnimation(.easeInOut(duration: 0.3)) { zoom.wrappedValue = nil }
                }
            }

            chart(shown)
                .frame(height: 140)
                .onAppear { scrub.color = selected.color }
                .onChange(of: selected) { _, newValue in
                    scrub.color = newValue.color
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let plotFrame = geo[proxy.plotFrame!]
                        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
                        let updateScrub: (CGPoint) -> Void = { loc in
                            let x = loc.x - plotFrame.origin.x
                            if let distInUnits: Double = proxy.value(atX: x) {
                                let dist = distInUnits * metersPerUnit
                                scrub.distance = max(domain.lowerBound, min(dist, domain.upperBound))
                            }
                        }
                        ZStack(alignment: .topLeading) {
                            ChartPinchBand(
                                scrub: scrub,
                                proxy: proxy,
                                plotFrame: plotFrame,
                                metersPerUnit: metersPerUnit)
                            ChartScrubRule(
                                scrub: scrub,
                                proxy: proxy,
                                plotFrame: plotFrame,
                                metersPerUnit: metersPerUnit)
                            LongPressScrubOverlay(
                                onBegan: { loc in
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        scrubActive = true
                                    }
                                    updateScrub(loc)
                                },
                                onChanged: updateScrub,
                                onEnded: {
                                    withAnimation(.easeInOut(duration: 0.2)) {
                                        scrubActive = false
                                    }
                                    scrub.distance = nil
                                },
                                onPinchChanged: { x1, x2 in
                                    scrub.pinch = chartPinchRange(
                                        x1, x2, proxy: proxy, plotFrame: plotFrame,
                                        metersPerUnit: metersPerUnit, domain: domain)
                                },
                                onPinchEnded: {
                                    if let range = scrub.pinch,
                                        range.upperBound - range.lowerBound >= chartMinimumZoomSpan
                                    {
                                        withAnimation(.easeInOut(duration: 0.3)) { zoom.wrappedValue = range }
                                    }
                                    scrub.pinch = nil
                                }
                            )
                        }
                    }
                }

            toggleBar

            RideScrubFooter(
                scrub: scrub,
                active: scrubActive,
                selected: selected,
                dataPoints: dataPoints)
        }
    }

    @ViewBuilder
    private func chart(_ shown: [ChartDataPoint]) -> some View {
        let unitLabel = currentUnits.distance.label
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        let xRange = (domain.lowerBound / metersPerUnit)...(domain.upperBound / metersPerUnit)
        let xTicks = chartDistanceTicks(in: xRange)
        let yDomain = yDomain(shown)
        let baseline = yDomain.lowerBound

        Chart {
            switch selected {
            case .elevation:
                ForEach(shown) { pt in
                    AreaMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("Elevation", elevationValue(pt.elevation))
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [selected.color.opacity(0.4), selected.color.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        y: .value("Elevation", elevationValue(pt.elevation))
                    )
                    .foregroundStyle(selected.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                if showGradeColors {
                    let bandTop = baseline + (yDomain.upperBound - yDomain.lowerBound) * 0.03
                    ForEach(
                        Array(
                            gradeBand(
                                distances: shown.map(\.distance),
                                grades: shown.map(\.grade)
                            ).enumerated()), id: \.offset
                    ) { _, seg in
                        RectangleMark(
                            xStart: .value("Start", seg.start / metersPerUnit),
                            xEnd: .value("End", seg.end / metersPerUnit),
                            yStart: .value("Base", baseline),
                            yEnd: .value("BandTop", bandTop)
                        )
                        .foregroundStyle(seg.color.opacity(0.85))
                    }
                }

            case .speed:
                ForEach(shown) { pt in
                    AreaMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("Speed", speedValue(pt.speed))
                    )
                    .foregroundStyle(selected.color.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        y: .value("Speed", speedValue(pt.speed))
                    )
                    .foregroundStyle(selected.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

            case .heartRate:
                ForEach(shown.filter { $0.heartRate > 0 }) { pt in
                    AreaMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("HR", pt.heartRate)
                    )
                    .foregroundStyle(selected.color.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        y: .value("HR", pt.heartRate)
                    )
                    .foregroundStyle(selected.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

            case .power:
                ForEach(shown.filter { $0.power > 0 }) { pt in
                    AreaMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("Power", pt.power)
                    )
                    .foregroundStyle(selected.color.opacity(0.3))
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Distance", pt.distance / metersPerUnit),
                        y: .value("Power", pt.power)
                    )
                    .foregroundStyle(selected.color)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }
            }

            ForEach(Array(splits.enumerated()), id: \.offset) { _, split in
                // Longer dashes than the scrub line's, so the two read apart.
                RuleMark(x: .value("Split", split.distance / metersPerUnit))
                    .foregroundStyle(split.color)
                    .lineStyle(StrokeStyle(lineWidth: 2, dash: [8, 4]))
            }
        }
        .chartXScale(domain: xRange)
        .chartXAxis {
            AxisMarks(preset: .aligned, values: xTicks) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                if let v = value.as(Double.self) {
                    AxisValueLabel(anchor: chartDistanceLabelAnchor(for: v, in: xRange)) {
                        Text("\(chartDistanceLabel(v)) \(unitLabel)")
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                if let v = value.as(Double.self) {
                    AxisValueLabel(anchor: chartYLabelAnchor(for: v, in: yDomain)) {
                        Text(yAxisLabel(v))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .chartPlotStyle { $0.clipped() }
    }

    private var toggleBar: some View {
        HStack(spacing: 6) {
            ForEach(availableMetrics, id: \.self) { metric in
                chartToggle(metric)
            }
        }
    }

    private func chartToggle(_ metric: RideChartMetric) -> some View {
        let isOn = selected == metric
        return Button {
            withAnimation(.easeInOut(duration: 0.2)) { selected = metric }
        } label: {
            Text(metric.label)
                .font(.caption2.weight(.medium))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(isOn ? metric.color.opacity(0.2) : Color.clear)
                .foregroundStyle(isOn ? metric.color : .secondary)
                .clipShape(Capsule())
                .overlay(
                    Capsule().stroke(isOn ? metric.color : .secondary.opacity(0.3), lineWidth: 1))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Unit Conversions

    private func elevationValue(_ meters: Double) -> Double {
        currentUnits.elevation == .feet ? meters * 3.28084 : meters
    }

    private func speedValue(_ mps: Double) -> Double {
        currentUnits.speed == .mph ? mps * 2.23694 : mps * 3.6
    }

    private func yAxisLabel(_ value: Double) -> String {
        switch selected {
        case .elevation:
            return "\(Int(value)) \(currentUnits.elevation == .feet ? "ft" : "m")"
        case .speed:
            return "\(Int(value)) \(currentUnits.speed == .mph ? "mph" : "km/h")"
        case .heartRate:
            return "\(Int(value)) bpm"
        case .power:
            return "\(Int(value)) W"
        }
    }

    /// Fits the points on screen, so a zoomed stretch fills the chart's height.
    private func yDomain(_ shown: [ChartDataPoint]) -> ClosedRange<Double> {
        let vals: [Double]
        switch selected {
        case .elevation:
            vals = shown.map { elevationValue($0.elevation) }
        case .speed:
            vals = shown.map { speedValue($0.speed) }
        case .heartRate:
            vals = shown.compactMap { $0.heartRate > 0 ? $0.heartRate : nil }
        case .power:
            vals = shown.compactMap { $0.power > 0 ? $0.power : nil }
        }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 100
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }

    /// "6.5 mi · ↑ 120 ft ↓ 80 ft · 24:10 · 16.1 mph". Time and speed only
    /// when the points carry time.
    private func zoomSummary(_ range: ClosedRange<Double>) -> String {
        let inRange = dataPoints.filter { range.contains($0.distance) }
        let (gain, loss) = chartGainLoss(inRange.map(\.elevation))
        var parts = [
            formatDistance(range.upperBound - range.lowerBound),
            "↑ \(formatElevation(gain)) ↓ \(formatElevation(loss))",
        ]
        if let start = inRange.first?.time, let end = inRange.last?.time, end > start {
            parts.append(formatChartDuration(end - start))
            var moving = 0.0
            for (a, b) in zip(inRange, inRange.dropFirst()) {
                if let ta = a.time, let tb = b.time, b.speed > 0.5 { moving += tb - ta }
            }
            if moving > 0 {
                parts.append(formatSpeed((range.upperBound - range.lowerBound) / moving))
            }
        }
        return parts.joined(separator: " · ")
    }
}

/// Hint / readout row below the ride charts. Isolated so per-frame scrub
/// updates re-render only this row.
private struct RideScrubFooter: View {
    @ObservedObject var scrub: ChartScrubState
    let active: Bool
    let selected: RideChartMetric
    let dataPoints: [ChartDataPoint]

    var body: some View {
        ZStack {
            // Hint — visible when not actively scrubbing.
            Text("Hold to scrub · Pinch to zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(active ? 0 : 1)

            // Readout — visible while scrubbing with a position.
            if let dist = scrub.distance, let pt = closestPoint(to: dist) {
                scrubReadout(pt)
                    .opacity(active ? 1 : 0)
            }
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.2), value: active)
        .animation(.easeInOut(duration: 0.2), value: scrub.distance == nil)
    }

    private func closestPoint(to distance: Double) -> ChartDataPoint? {
        dataPoints.min(by: { abs($0.distance - distance) < abs($1.distance - distance) })
    }

    @ViewBuilder
    private func scrubReadout(_ pt: ChartDataPoint) -> some View {
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        HStack(spacing: 16) {
            let distLabel = String(
                format: "%.1f %@", pt.distance / metersPerUnit, currentUnits.distance.label)
            Text(distLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            switch selected {
            case .elevation:
                Text(formatElevation(pt.elevation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected.color)
                Text(gradeLabel(pt.grade))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(gradeColor(pt.grade))
            case .speed:
                Text(formatSpeed(pt.speed))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected.color)
            case .heartRate:
                Text("\(Int(pt.heartRate)) bpm")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected.color)
            case .power:
                Text("\(Int(pt.power)) W")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected.color)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 2)
        .background(selected.color.opacity(0.1), in: Capsule())
    }
}

// MARK: - Route Elevation Chart

struct RouteElevationPoint {
    let distanceFromStart: Double
    let elevation: Double?
    /// Percent, 0 where the route has no elevation.
    let grade: Double
}

struct RouteElevationChartView: View {
    let points: [RouteElevationPoint]
    /// Written from the gesture only — observed by the scrub leaf views.
    let scrub: ChartScrubState
    /// The stretch the chart is zoomed to, in meters. See `RideChartsView.zoom`.
    var zoom: Binding<ClosedRange<Double>?> = .constant(nil)
    @State private var scrubActive = false
    @ObservedObject private var unitState = UnitState.shared
    @AppStorage(PhoneSettingsKeys.gradeColors) private var showGradeColors = true

    private var domain: ClosedRange<Double> {
        zoom.wrappedValue ?? 0...max(points.last?.distanceFromStart ?? 0, 1)
    }

    var body: some View {
        let _ = unitState.preferences
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        let unitLabel = currentUnits.distance.label
        let elevPoints = chartPoints(
            points.filter { $0.elevation != nil }, distance: \.distanceFromStart, in: domain)
        let xRange = (domain.lowerBound / metersPerUnit)...(domain.upperBound / metersPerUnit)
        let xTicks = chartDistanceTicks(in: xRange)
        let yDomain = elevationDomain(elevPoints)
        let baseline = yDomain.lowerBound

        VStack(spacing: 8) {
            if let range = zoom.wrappedValue {
                ChartZoomReadout(text: zoomSummary(range), color: .green) {
                    withAnimation(.easeInOut(duration: 0.3)) { zoom.wrappedValue = nil }
                }
            }

            Chart {
                ForEach(Array(elevPoints.enumerated()), id: \.offset) { _, pt in
                    let elev = elevationValue(pt.elevation ?? 0)
                    AreaMark(
                        x: .value("Distance", pt.distanceFromStart / metersPerUnit),
                        yStart: .value("Baseline", baseline),
                        yEnd: .value("Elevation", elev)
                    )
                    .foregroundStyle(
                        .linearGradient(
                            colors: [.green.opacity(0.4), .green.opacity(0.05)],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    )
                    .interpolationMethod(.catmullRom)
                    LineMark(
                        x: .value("Distance", pt.distanceFromStart / metersPerUnit),
                        y: .value("Elevation", elev)
                    )
                    .foregroundStyle(.green)
                    .interpolationMethod(.catmullRom)
                    .lineStyle(StrokeStyle(lineWidth: 1.5))
                }

                if showGradeColors {
                    let bandTop = baseline + (yDomain.upperBound - yDomain.lowerBound) * 0.03
                    ForEach(
                        Array(
                            gradeBand(
                                distances: elevPoints.map(\.distanceFromStart),
                                grades: elevPoints.map(\.grade)
                            ).enumerated()), id: \.offset
                    ) { _, seg in
                        RectangleMark(
                            xStart: .value("Start", seg.start / metersPerUnit),
                            xEnd: .value("End", seg.end / metersPerUnit),
                            yStart: .value("Base", baseline),
                            yEnd: .value("BandTop", bandTop)
                        )
                        .foregroundStyle(seg.color.opacity(0.85))
                    }
                }

                ForEach(xTicks.filter { $0 > xRange.lowerBound }, id: \.self) { tick in
                    RuleMark(x: .value("Marker", tick))
                        .foregroundStyle(.secondary.opacity(0.4))
                        .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                }

            }
            .chartXScale(domain: xRange)
            .chartXAxis {
                AxisMarks(preset: .aligned, values: xTicks) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    if let v = value.as(Double.self) {
                        AxisValueLabel(anchor: chartDistanceLabelAnchor(for: v, in: xRange)) {
                            Text("\(chartDistanceLabel(v)) \(unitLabel)")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    if let v = value.as(Double.self) {
                        AxisValueLabel(anchor: chartYLabelAnchor(for: v, in: yDomain)) {
                            Text("\(Int(v)) \(currentUnits.elevation == .feet ? "ft" : "m")")
                                .font(.system(size: 9))
                        }
                    }
                }
            }
            .chartYScale(domain: yDomain)
            .chartLegend(.hidden)
            .chartPlotStyle { $0.clipped() }
            .frame(height: 140)
            .chartOverlay { proxy in
                GeometryReader { geo in
                    let plotFrame = geo[proxy.plotFrame!]
                    let updateScrub: (CGPoint) -> Void = { loc in
                        let x = loc.x - plotFrame.origin.x
                        if let distInUnits: Double = proxy.value(atX: x) {
                            let dist = distInUnits * metersPerUnit
                            scrub.distance = max(domain.lowerBound, min(dist, domain.upperBound))
                        }
                    }
                    ZStack(alignment: .topLeading) {
                        ChartPinchBand(
                            scrub: scrub,
                            proxy: proxy,
                            plotFrame: plotFrame,
                            metersPerUnit: metersPerUnit)
                        ChartScrubRule(
                            scrub: scrub,
                            proxy: proxy,
                            plotFrame: plotFrame,
                            metersPerUnit: metersPerUnit)
                        LongPressScrubOverlay(
                            onBegan: { loc in
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrubActive = true
                                }
                                updateScrub(loc)
                            },
                            onChanged: updateScrub,
                            onEnded: {
                                withAnimation(.easeInOut(duration: 0.2)) {
                                    scrubActive = false
                                }
                                scrub.distance = nil
                            },
                            onPinchChanged: { x1, x2 in
                                scrub.pinch = chartPinchRange(
                                    x1, x2, proxy: proxy, plotFrame: plotFrame,
                                    metersPerUnit: metersPerUnit, domain: domain)
                            },
                            onPinchEnded: {
                                if let range = scrub.pinch,
                                    range.upperBound - range.lowerBound >= chartMinimumZoomSpan
                                {
                                    withAnimation(.easeInOut(duration: 0.3)) { zoom.wrappedValue = range }
                                }
                                scrub.pinch = nil
                            }
                        )
                    }
                }
            }

            RouteScrubFooter(scrub: scrub, active: scrubActive, points: points)
        }
    }

    /// "6.5 mi · ↑ 120 ft ↓ 80 ft" for the zoomed stretch.
    private func zoomSummary(_ range: ClosedRange<Double>) -> String {
        let elevations = points
            .filter { range.contains($0.distanceFromStart) }
            .compactMap(\.elevation)
        let (gain, loss) = chartGainLoss(elevations)
        return "\(formatDistance(range.upperBound - range.lowerBound)) · ↑ \(formatElevation(gain)) ↓ \(formatElevation(loss))"
    }

    private func elevationValue(_ meters: Double) -> Double {
        currentUnits.elevation == .feet ? meters * 3.28084 : meters
    }

    private func elevationDomain(_ pts: [RouteElevationPoint]) -> ClosedRange<Double> {
        let vals = pts.compactMap { $0.elevation.map { elevationValue($0) } }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 100
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }
}

/// Hint / readout row below the route elevation chart. Isolated so per-frame
/// scrub updates re-render only this row.
private struct RouteScrubFooter: View {
    @ObservedObject var scrub: ChartScrubState
    let active: Bool
    let points: [RouteElevationPoint]

    var body: some View {
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        ZStack {
            Text("Hold to scrub · Pinch to zoom")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(active ? 0 : 1)

            if let dist = scrub.distance, let pt = closestPoint(to: dist), let elev = pt.elevation {
                HStack(spacing: 16) {
                    Text(
                        String(format: "%.1f %@", dist / metersPerUnit, currentUnits.distance.label)
                    )
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                    Text(formatElevation(elev))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                    Text(gradeLabel(pt.grade))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(gradeColor(pt.grade))
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1), in: Capsule())
                .opacity(active ? 1 : 0)
            }
        }
        .frame(height: 26)
        .animation(.easeInOut(duration: 0.2), value: active)
        .animation(.easeInOut(duration: 0.2), value: scrub.distance == nil)
    }

    private func closestPoint(to targetDist: Double) -> RouteElevationPoint? {
        points
            .filter { $0.elevation != nil }
            .min(by: {
                abs($0.distanceFromStart - targetDist) < abs($1.distanceFromStart - targetDist)
            })
    }
}

// MARK: - Data Building

func buildRideChartData(from trackURL: URL, segmentCount: Int = 1200) -> (
    points: [ChartDataPoint], hasHR: Bool, hasPower: Bool
) {
    guard let data = try? Data(contentsOf: trackURL) else { return ([], false, false) }
    return buildRideChartData(points: TrackEncoder.decodeV5Full(data), segmentCount: segmentCount)
}

/// About 1200 chunks by default: plenty for a zoomed-in chart, and the chart
/// only draws ~300 of them at a time.
func buildRideChartData(points fullPoints: [TrackPoint5], segmentCount: Int = 1200) -> (
    points: [ChartDataPoint], hasHR: Bool, hasPower: Bool
) {
    guard fullPoints.count >= 2 else { return ([], false, false) }

    var distances: [Double] = []
    distances.reserveCapacity(fullPoints.count)
    var cumulativeDist: Double = 0
    var lastLoc: CLLocation?
    for pt in fullPoints {
        let loc = CLLocation(latitude: pt.lat, longitude: pt.lon)
        if let prev = lastLoc {
            cumulativeDist += loc.distance(from: prev)
        }
        lastLoc = loc
        distances.append(cumulativeDist)
    }

    // Some saved points have altitude exactly 0, which would read as a cliff.
    let profile = GradeProfile(
        fullPoints.indices.compactMap { idx in
            fullPoints[idx].altitude == 0 ? nil : (distances[idx], fullPoints[idx].altitude)
        })

    let chunkSize = max(1, fullPoints.count / segmentCount)
    var chartPoints: [ChartDataPoint] = []
    var hasHR = false
    var hasPower = false
    var chunkStartDist: Double = 0

    var i = 0
    while i < fullPoints.count {
        let end = min(i + chunkSize, fullPoints.count)
        let chunk = fullPoints[i..<end]
        let chunkEndDist = distances[end - 1]

        let avgElev = chunk.map(\.altitude).reduce(0, +) / Double(chunk.count)
        let avgSpeed: Double = {
            let first = chunk.first!
            let last = chunk.last!
            let dt = last.timestamp - first.timestamp
            if dt > 0 {
                let firstLoc = CLLocation(latitude: first.lat, longitude: first.lon)
                let lastLoc = CLLocation(latitude: last.lat, longitude: last.lon)
                return lastLoc.distance(from: firstLoc) / dt
            }
            return 0
        }()
        let hrValues = chunk.filter { $0.heartRate > 0 }
        let avgHR =
            hrValues.isEmpty ? 0 : hrValues.map(\.heartRate).reduce(0, +) / Double(hrValues.count)
        let pwValues = chunk.filter { $0.power > 0 }
        let avgPower =
            pwValues.isEmpty ? 0 : pwValues.map(\.power).reduce(0, +) / Double(pwValues.count)

        if avgHR > 0 { hasHR = true }
        if avgPower > 0 { hasPower = true }

        // Ride tracks only have GPS altitude, so grade needs a wide window.
        let chunkLength = chunkEndDist - chunkStartDist
        let grade = profile.grade(
            at: (chunkStartDist + chunkEndDist) / 2,
            halfWindow: max(150, chunkLength / 2))

        chartPoints.append(
            ChartDataPoint(
                distance: chunkEndDist,
                elevation: avgElev,
                speed: avgSpeed,
                heartRate: avgHR,
                power: avgPower,
                grade: grade,
                time: chunk.last!.timestamp - fullPoints[0].timestamp
            ))

        chunkStartDist = chunkEndDist
        i += chunkSize
    }

    return (chartPoints, hasHR, hasPower)
}

// MARK: - Preview

/// Mock chart points with grade read off the mock profile, like the real builder.
private func previewChartData(count: Int, spacing: Double, elevation: (Double) -> Double)
    -> [ChartDataPoint]
{
    let dists = (0..<count).map { Double($0) * spacing }
    let profile = GradeProfile(dists.map { ($0, elevation($0)) })
    return dists.enumerated().map { i, dist in
        let phase = Double(i) / Double(count)
        return ChartDataPoint(
            distance: dist,
            elevation: elevation(dist),
            speed: max(0, 5.0 + 3.0 * sin(phase * .pi * 5)),
            heartRate: 130 + 30 * sin(phase * .pi * 4),
            power: max(0, 180 + 80 * sin(phase * .pi * 6)),
            grade: profile.grade(at: dist, halfWindow: max(150, spacing / 2)))
    }
}

/// Flat, then climbs at 4, 8 and 12%, a -8% descent, and flat again, 1 km each.
private func previewSteepElevation(_ dist: Double) -> Double {
    let legs: [Double] = [0, 0.04, 0.08, 0.12, -0.08, 0]
    var elev = 180.0
    for (i, g) in legs.enumerated() {
        let legStart = Double(i) * 1000
        guard dist > legStart else { break }
        elev += min(dist - legStart, 1000) * g
    }
    return elev
}

private func previewScrub(at distance: Double) -> ChartScrubState {
    let scrub = ChartScrubState()
    scrub.distance = distance
    return scrub
}

#Preview("Ride Charts Panel") {
    let mockData = previewChartData(count: 200, spacing: 250) { dist in
        let phase = dist / 50_000
        return 200 + 150 * sin(phase * .pi * 3) + 50 * sin(phase * .pi * 7)
    }

    VStack(spacing: 6) {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 4)
            .padding(.top, 8)

        RideChartsView(
            dataPoints: mockData, hasHeartRate: true, hasPower: true, scrub: ChartScrubState())

        HStack(spacing: 6) {
            Circle().fill(Color.primary).frame(width: 6, height: 6)
            Circle().fill(Color.secondary.opacity(0.4)).frame(width: 6, height: 6)
        }
    }
    .padding(.horizontal, 16)
    .padding(.bottom, 8)
    .background(
        RoundedRectangle(cornerRadius: 16)
            .fill(.ultraThinMaterial)
            .shadow(radius: 12, y: 4)
    )
    .padding(.horizontal, 12)
}

#Preview("Grade Band Tiers") {
    let mockData = previewChartData(count: 120, spacing: 50, elevation: previewSteepElevation)
    RideChartsView(
        dataPoints: mockData, hasHeartRate: false, hasPower: false, scrub: ChartScrubState()
    )
    .padding(.horizontal, 16)
}

#Preview("Multi-ride splits") {
    let mockData = previewChartData(count: 120, spacing: 50, elevation: previewSteepElevation)
    RideChartsView(
        dataPoints: mockData, hasHeartRate: false, hasPower: false, scrub: ChartScrubState(),
        splits: [
            ChartSplit(distance: 2000, color: .yellow), ChartSplit(distance: 4200, color: .indigo),
        ]
    )
    .padding(.horizontal, 16)
}

#Preview("Zoomed chart") {
    @Previewable @State var zoom: ClosedRange<Double>? = 1000...4500
    let mockData = previewChartData(count: 240, spacing: 25, elevation: previewSteepElevation)
        .enumerated().map { i, pt in
            ChartDataPoint(
                distance: pt.distance, elevation: pt.elevation, speed: 6, heartRate: pt.heartRate,
                power: pt.power, grade: pt.grade, time: Double(i) * 4)
        }
    RideChartsView(
        dataPoints: mockData, hasHeartRate: true, hasPower: true, scrub: ChartScrubState(),
        zoom: $zoom)
        .padding(.horizontal, 16)
}

#Preview("Grade Readout") {
    let mockData = previewChartData(count: 120, spacing: 50, elevation: previewSteepElevation)
    // Middle of the flat, 8% climb and -8% descent legs.
    VStack(spacing: 12) {
        ForEach([500.0, 2500, 4500], id: \.self) { dist in
            RideScrubFooter(
                scrub: previewScrub(at: dist), active: true, selected: .elevation,
                dataPoints: mockData)
        }
    }
    .padding()
}

func buildRouteElevationData(from route: Route) -> [RouteElevationPoint] {
    let pts = route.points
    guard pts.count >= 2 else { return [] }

    var cumDist: Double = 0
    var distances: [Double] = []
    distances.reserveCapacity(pts.count)
    for i in 0..<pts.count {
        if i > 0 {
            let prev = CLLocation(latitude: pts[i - 1].lat, longitude: pts[i - 1].lon)
            let cur = CLLocation(latitude: pts[i].lat, longitude: pts[i].lon)
            cumDist += cur.distance(from: prev)
        }
        distances.append(cumDist)
    }

    let profile = GradeProfile(
        pts.indices.compactMap { i in
            pts[i].elevation.map { (distances[i], $0) }
        })

    // Enough points that a zoomed chart keeps its detail. The chart draws
    // ~300 of them at a time.
    let target = 1500
    let step = max(1, pts.count / target)
    var indices = Array(stride(from: 0, to: pts.count, by: step))
    if indices.last != pts.count - 1 { indices.append(pts.count - 1) }

    // Route elevation comes from map data, so a tighter window than rides works.
    let halfWindow = max(100, cumDist / Double(indices.count) / 2)
    return indices.map { i in
        RouteElevationPoint(
            distanceFromStart: distances[i],
            elevation: pts[i].elevation,
            grade: pts[i].elevation == nil
                ? 0 : profile.grade(at: distances[i], halfWindow: halfWindow))
    }
}

/// "1:05:30" or "24:10".
func formatChartDuration(_ seconds: Double) -> String {
    let total = Int(seconds.rounded())
    let h = total / 3600, m = (total % 3600) / 60, sec = total % 60
    return h > 0 ? String(format: "%d:%02d:%02d", h, m, sec) : String(format: "%d:%02d", m, sec)
}

/// The zoomed stretch on a map: a white-cased black line with A and B at
/// its ends. Each segment is a run of the track's real points, so the line
/// sits right on top of the track through every bend.
struct ChartZoomMapHighlight: MapContent {
    let segments: [[CLLocationCoordinate2D]]

    var body: some MapContent {
        ForEach(Array(segments.enumerated()), id: \.offset) { _, coords in
            if coords.count >= 2 {
                MapPolyline(coordinates: coords)
                    .stroke(.white, style: StrokeStyle(lineWidth: 9, lineCap: .round, lineJoin: .round))
                MapPolyline(coordinates: coords)
                    .stroke(.black, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
            }
        }
        if let first = segments.first?.first {
            Annotation("", coordinate: first) { ChartZoomPin(letter: "A") }
        }
        if let last = segments.last?.last {
            Annotation("", coordinate: last) { ChartZoomPin(letter: "B") }
        }
    }
}

/// The track's own points between `range`'s ends, with the two ends
/// interpolated onto the track. `distance(i)` must rise with `i`.
func trackCoordinates(
    in range: ClosedRange<Double>,
    count: Int,
    distance: (Int) -> Double,
    coordinate: (Int) -> CLLocationCoordinate2D
) -> [CLLocationCoordinate2D] {
    guard count >= 2 else { return [] }

    func firstIndex(atLeast value: Double) -> Int {
        var lo = 0, hi = count
        while lo < hi {
            let mid = (lo + hi) / 2
            if distance(mid) < value { lo = mid + 1 } else { hi = mid }
        }
        return lo
    }

    func point(at value: Double) -> CLLocationCoordinate2D {
        let i = min(max(firstIndex(atLeast: value), 1), count - 1)
        let span = distance(i) - distance(i - 1)
        let t = span > 0 ? max(0, min(1, (value - distance(i - 1)) / span)) : 0
        let a = coordinate(i - 1), b = coordinate(i)
        return CLLocationCoordinate2D(
            latitude: a.latitude + (b.latitude - a.latitude) * t,
            longitude: a.longitude + (b.longitude - a.longitude) * t)
    }

    let start = firstIndex(atLeast: range.lowerBound)
    let end = firstIndex(atLeast: range.upperBound)  // first point past the stretch
    let inner = (start..<max(start, min(end, count))).map(coordinate)
    return [point(at: range.lowerBound)] + inner + [point(at: range.upperBound)]
}

/// The parts of a run of track points (`start...end`) that fall outside
/// `zoom`, cut exactly at its ends. Drawing these and the zoom highlight
/// for the middle, rather than the whole run under the highlight, keeps the
/// two from overlapping. A run that misses the zoom comes back whole.
func trackPieces(
    outside zoom: ClosedRange<Double>,
    from start: Int,
    to end: Int,
    count: Int,
    distance: (Int) -> Double,
    coordinate: (Int) -> CLLocationCoordinate2D
) -> [[CLLocationCoordinate2D]] {
    guard start < end, end < count else { return [] }
    let d0 = distance(start), d1 = distance(end)
    if d1 <= zoom.lowerBound || d0 >= zoom.upperBound {
        return [(start...end).map(coordinate)]
    }
    var pieces: [[CLLocationCoordinate2D]] = []
    if d0 < zoom.lowerBound {
        pieces.append(trackCoordinates(in: d0...zoom.lowerBound, count: count, distance: distance, coordinate: coordinate))
    }
    if d1 > zoom.upperBound {
        pieces.append(trackCoordinates(in: zoom.upperBound...d1, count: count, distance: distance, coordinate: coordinate))
    }
    return pieces
}

/// One piece of a track line to draw.
struct MapLinePiece: Identifiable {
    let id: String
    let coords: [CLLocationCoordinate2D]
    let color: Color
}

private struct ChartZoomPin: View {
    let letter: String

    var body: some View {
        Text(letter)
            .font(.caption2.weight(.bold))
            .foregroundStyle(.white)
            .frame(width: 20, height: 20)
            .background(Circle().fill(.black))
            .overlay(Circle().stroke(.white, lineWidth: 2))
    }
}
