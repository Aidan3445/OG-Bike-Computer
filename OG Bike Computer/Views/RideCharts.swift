//
//  RideCharts.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/10/26.
//

import SwiftUI
import Charts
import CoreLocation
import UIKit

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

    func makeUIView(context: Context) -> UIView {
        let view = UIView()
        view.backgroundColor = .clear
        view.isUserInteractionEnabled = true

        let recognizer = UILongPressGestureRecognizer(
            target: context.coordinator,
            action: #selector(Coordinator.handle(_:)))
        recognizer.minimumPressDuration = minimumDuration
        recognizer.allowableMovement = .greatestFiniteMagnitude // don't cancel once activated
        recognizer.cancelsTouchesInView = false
        recognizer.delaysTouchesBegan = false
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = context.coordinator

        context.coordinator.view = view
        context.coordinator.recognizer = recognizer
        view.addGestureRecognizer(recognizer)
        return view
    }

    func updateUIView(_ uiView: UIView, context: Context) {
        context.coordinator.onBegan = onBegan
        context.coordinator.onChanged = onChanged
        context.coordinator.onEnded = onEnded
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

        init(onBegan: @escaping (CGPoint) -> Void,
             onChanged: @escaping (CGPoint) -> Void,
             onEnded: @escaping () -> Void) {
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
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
            true
        }

        // Reserve the leading edge for the NavigationStack swipe-back gesture —
        // touches that start within 40pt of the left edge never arm the scrubber.
        func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer,
                               shouldReceive touch: UITouch) -> Bool {
            guard let view = view else { return true }
            let x = touch.location(in: view).x
            return x >= 40
        }
    }
}

// MARK: - Data Model

struct ChartDataPoint: Identifiable {
    let id = UUID()
    let distance: Double      // meters from start
    let elevation: Double     // meters
    let speed: Double         // m/s
    let heartRate: Double     // bpm (0 = no data)
    let power: Double         // watts (0 = no data)
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

struct RideChartsView: View {
    let dataPoints: [ChartDataPoint]
    let hasHeartRate: Bool
    let hasPower: Bool
    /// Scrub position in meters from start; nil when not scrubbing.
    @Binding var scrubDistance: Double?
    /// Optional binding that surfaces the currently-selected chart's color
    /// so a parent (e.g. the map view's scrub dot) can match it. The chart
    /// itself doesn't need this — it's purely for cross-view styling.
    var scrubColor: Binding<Color>? = nil

    @State private var selected: RideChartMetric = .elevation
    @State private var scrubActive = false

    private var availableMetrics: [RideChartMetric] {
        var metrics: [RideChartMetric] = [.elevation, .speed]
        if hasHeartRate { metrics.append(.heartRate) }
        if hasPower { metrics.append(.power) }
        return metrics
    }

    var body: some View {
        VStack(spacing: 8) {
            chart
                .frame(height: 140)
                .onAppear { scrubColor?.wrappedValue = selected.color }
                .onChange(of: selected) { _, newValue in
                    scrubColor?.wrappedValue = newValue.color
                }
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        let updateScrub: (CGPoint) -> Void = { loc in
                            let plotOrigin = geo[proxy.plotFrame!].origin
                            let x = loc.x - plotOrigin.x
                            let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
                            if let distInUnits: Double = proxy.value(atX: x) {
                                let dist = distInUnits * metersPerUnit
                                let maxDist = dataPoints.last?.distance ?? 0
                                scrubDistance = max(0, min(dist, maxDist))
                            }
                        }
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
                                scrubDistance = nil
                            }
                        )
                    }
                }

            toggleBar

            scrubFooter
        }
    }

    @ViewBuilder
    private var scrubFooter: some View {
        ZStack {
            // Hint — visible when not actively scrubbing.
            Text("Tap and hold to scrub")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(scrubActive ? 0 : 1)

            // Readout — visible while scrubbing with a position.
            if let scrub = scrubDistance, let pt = closestPoint(to: scrub) {
                scrubReadout(pt)
                    .opacity(scrubActive ? 1 : 0)
            }
        }
        .frame(height: 22)
        .animation(.easeInOut(duration: 0.2), value: scrubActive)
        .animation(.easeInOut(duration: 0.2), value: scrubDistance == nil)
    }

    private func closestPoint(to distance: Double) -> ChartDataPoint? {
        dataPoints.min(by: { abs($0.distance - distance) < abs($1.distance - distance) })
    }

    @ViewBuilder
    private func scrubReadout(_ pt: ChartDataPoint) -> some View {
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        HStack(spacing: 16) {
            let distLabel = String(format: "%.1f %@", pt.distance / metersPerUnit, currentUnits.distance.label)
            Text(distLabel)
                .font(.caption2.weight(.medium))
                .foregroundStyle(.secondary)
            switch selected {
            case .elevation:
                Text(formatElevation(pt.elevation))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(selected.color)
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

    @ViewBuilder
    private var chart: some View {
        let unitLabel = currentUnits.distance.label
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        let maxDist = (dataPoints.last?.distance ?? 0) / metersPerUnit
        let baseline = yDomain.lowerBound

        Chart {
            switch selected {
            case .elevation:
                ForEach(dataPoints) { pt in
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

            case .speed:
                ForEach(dataPoints) { pt in
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
                ForEach(dataPoints.filter { $0.heartRate > 0 }) { pt in
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
                ForEach(dataPoints.filter { $0.power > 0 }) { pt in
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
            // Scrub rule line
            if let scrub = scrubDistance {
                let scrubInUnits = scrub / metersPerUnit
                RuleMark(x: .value("Scrub", scrubInUnits))
                    .foregroundStyle(selected.color.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartXScale(domain: 0...maxDist)
        .chartXAxis {
            // Anchor labels to the leading edge of their tick so the rightmost
            // label doesn't get clipped at the chart edge.
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(anchor: .topLeading) {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) \(unitLabel)")
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text(yAxisLabel(v))
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYScale(domain: yDomain)
        .chartLegend(.hidden)
        .clipped()
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
                .overlay(Capsule().stroke(isOn ? metric.color : .secondary.opacity(0.3), lineWidth: 1))
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

    private var yDomain: ClosedRange<Double> {
        let vals: [Double]
        switch selected {
        case .elevation:
            vals = dataPoints.map { elevationValue($0.elevation) }
        case .speed:
            vals = dataPoints.map { speedValue($0.speed) }
        case .heartRate:
            vals = dataPoints.compactMap { $0.heartRate > 0 ? $0.heartRate : nil }
        case .power:
            vals = dataPoints.compactMap { $0.power > 0 ? $0.power : nil }
        }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 100
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }
}

// MARK: - Route Elevation Chart

struct RouteElevationChartView: View {
    let points: [ProcessedPoint]
    @Binding var scrubDistance: Double?
    @State private var scrubActive = false

    var body: some View {
        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
        let unitLabel = currentUnits.distance.label
        let elevPoints = points.filter { $0.elevation != nil }
        let maxDist = (points.last?.distanceFromStart ?? 0) / metersPerUnit
        let baseline = elevationDomain(elevPoints).lowerBound

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

            // Mile marker rule lines
            let totalDist = points.last?.distanceFromStart ?? 0
            let interval = distanceMarkerInterval
            let markerCount = Int(totalDist / (interval * metersPerUnit))
            ForEach(1...max(1, markerCount), id: \.self) { i in
                RuleMark(x: .value("Marker", Double(i) * interval))
                    .foregroundStyle(.secondary.opacity(0.4))
                    .lineStyle(StrokeStyle(lineWidth: 0.5, dash: [4, 3]))
                    .annotation(position: .top, alignment: .center) {
                        Text("\(Int(Double(i) * interval)) \(unitLabel)")
                            .font(.system(size: 8))
                            .foregroundStyle(.secondary)
                    }
            }

            // Scrub rule line
            if let scrub = scrubDistance {
                RuleMark(x: .value("Scrub", scrub / metersPerUnit))
                    .foregroundStyle(Color.green.opacity(0.8))
                    .lineStyle(StrokeStyle(lineWidth: 1.5, dash: [4, 3]))
            }
        }
        .chartXScale(domain: 0...maxDist)
        .chartXAxis {
            // Anchor labels to the leading edge of their tick so the rightmost
            // label doesn't get clipped at the chart edge.
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel(anchor: .topLeading) {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) \(unitLabel)")
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(position: .leading, values: .automatic(desiredCount: 4)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
                    if let v = value.as(Double.self) {
                        Text("\(Int(v)) \(currentUnits.elevation == .feet ? "ft" : "m")")
                            .font(.system(size: 9))
                    }
                }
            }
        }
        .chartYScale(domain: elevationDomain(elevPoints))
        .chartLegend(.hidden)
        .clipped()
        .frame(height: 140)
        .chartOverlay { proxy in
            GeometryReader { geo in
                let updateScrub: (CGPoint) -> Void = { loc in
                    let plotOrigin = geo[proxy.plotFrame!].origin
                    let x = loc.x - plotOrigin.x
                    if let distInUnits: Double = proxy.value(atX: x) {
                        let dist = distInUnits * metersPerUnit
                        let maxDistMeters = points.last?.distanceFromStart ?? 0
                        scrubDistance = max(0, min(dist, maxDistMeters))
                    }
                }
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
                        scrubDistance = nil
                    }
                )
            }
        }

        ZStack {
            Text("Tap and hold to scrub")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .opacity(scrubActive ? 0 : 1)

            if let scrub = scrubDistance, let elev = elevationAtDistance(scrub) {
                HStack(spacing: 16) {
                    Text(String(format: "%.1f %@", scrub / metersPerUnit, currentUnits.distance.label))
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                    Text(formatElevation(elev))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.green)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.green.opacity(0.1), in: Capsule())
                .opacity(scrubActive ? 1 : 0)
            }
        }
        .frame(height: 26)
        .animation(.easeInOut(duration: 0.2), value: scrubActive)
        .animation(.easeInOut(duration: 0.2), value: scrubDistance == nil)
    }

    private func elevationAtDistance(_ targetDist: Double) -> Double? {
        guard !points.isEmpty else { return nil }
        let sorted = points.filter { $0.elevation != nil }
        if let exact = sorted.min(by: { abs($0.distanceFromStart - targetDist) < abs($1.distanceFromStart - targetDist) }) {
            return exact.elevation
        }
        return nil
    }

    private func elevationValue(_ meters: Double) -> Double {
        currentUnits.elevation == .feet ? meters * 3.28084 : meters
    }

    private func elevationDomain(_ pts: [ProcessedPoint]) -> ClosedRange<Double> {
        let vals = pts.compactMap { $0.elevation.map { elevationValue($0) } }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 100
        let pad = max((hi - lo) * 0.1, 1)
        return (lo - pad)...(hi + pad)
    }

    private var distanceMarkerInterval: Double {
        currentUnits.distance == .miles ? 5 : 5
    }
}

// MARK: - Data Building

func buildRideChartData(from trackURL: URL, segmentCount: Int = 200) -> (points: [ChartDataPoint], hasHR: Bool, hasPower: Bool) {
    guard let data = try? Data(contentsOf: trackURL) else { return ([], false, false) }
    let fullPoints = TrackEncoder.decodeV5Full(data)
    guard fullPoints.count >= 2 else { return ([], false, false) }

    let chunkSize = max(1, fullPoints.count / segmentCount)
    var chartPoints: [ChartDataPoint] = []
    var cumulativeDist: Double = 0
    var hasHR = false
    var hasPower = false
    var lastLoc: CLLocation?

    var i = 0
    while i < fullPoints.count {
        let end = min(i + chunkSize, fullPoints.count)
        let chunk = fullPoints[i..<end]

        // Accumulate distance
        for pt in chunk {
            let loc = CLLocation(latitude: pt.lat, longitude: pt.lon)
            if let prev = lastLoc {
                cumulativeDist += loc.distance(from: prev)
            }
            lastLoc = loc
        }

        // Average the chunk
        let avgElev = chunk.map(\.altitude).reduce(0, +) / Double(chunk.count)
        let avgSpeed: Double = {
            // Compute speed from distance/time for the chunk
            let first = chunk.first!, last = chunk.last!
            let dt = last.timestamp - first.timestamp
            if dt > 0 {
                let firstLoc = CLLocation(latitude: first.lat, longitude: first.lon)
                let lastLoc = CLLocation(latitude: last.lat, longitude: last.lon)
                return lastLoc.distance(from: firstLoc) / dt
            }
            return 0
        }()
        let hrValues = chunk.filter { $0.heartRate > 0 }
        let avgHR = hrValues.isEmpty ? 0 : hrValues.map(\.heartRate).reduce(0, +) / Double(hrValues.count)
        let pwValues = chunk.filter { $0.power > 0 }
        let avgPower = pwValues.isEmpty ? 0 : pwValues.map(\.power).reduce(0, +) / Double(pwValues.count)

        if avgHR > 0 { hasHR = true }
        if avgPower > 0 { hasPower = true }

        chartPoints.append(ChartDataPoint(
            distance: cumulativeDist,
            elevation: avgElev,
            speed: avgSpeed,
            heartRate: avgHR,
            power: avgPower
        ))

        i += chunkSize
    }

    return (chartPoints, hasHR, hasPower)
}

// MARK: - Preview

#Preview("Ride Charts Panel") {
    let mockData: [ChartDataPoint] = (0..<200).map { i in
        let dist = Double(i) * 250.0 // ~50km total
        let phase = Double(i) / 200.0
        let elevation = 200 + 150 * sin(phase * .pi * 3) + 50 * sin(phase * .pi * 7)
        let speed = max(0, 5.0 + 3.0 * sin(phase * .pi * 5) + Double.random(in: -1...1))
        let hr = 130 + 30 * sin(phase * .pi * 4) + Double.random(in: -5...5)
        let power = max(0, 180 + 80 * sin(phase * .pi * 6) + Double.random(in: -20...20))
        return ChartDataPoint(distance: dist, elevation: elevation, speed: speed, heartRate: hr, power: power)
    }

    VStack(spacing: 6) {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 4)
            .padding(.top, 8)

        RideChartsView(dataPoints: mockData, hasHeartRate: true, hasPower: true, scrubDistance: .constant(nil))

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

func buildRouteElevationData(from route: Route) -> [ProcessedPoint] {
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
            bearingToNext: 0
        ))
    }

    // Downsample for chart performance
    let target = 300
    if processed.count > target {
        let step = processed.count / target
        var downsampled: [ProcessedPoint] = []
        for i in stride(from: 0, to: processed.count, by: step) {
            downsampled.append(processed[i])
        }
        if let last = processed.last, downsampled.last?.distanceFromStart != last.distanceFromStart {
            downsampled.append(last)
        }
        return downsampled
    }
    return processed
}
