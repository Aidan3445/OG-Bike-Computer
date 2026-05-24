//
//  ElevationChart.swift
//  OG Bike Computer
//
//  Reusable elevation chart used by the watch's live screen and by the phone's
//  settings preview. Pure presentation — callers supply samples, current
//  position, config, and a binding for the mode toggle.
//

import SwiftUI
import Charts
internal import _LocationEssentials

struct ElevationChart: View {
    let samples: [ElevationSample]
    let pois: [RoutePOI]
    let currentDistance: Double
    let currentElevation: Double
    let liveGain: Double
    let config: ElevationScreenConfig
    let showWaypoints: Bool
    @Binding var mode: ElevationDefaultTab

    var body: some View {
        VStack(spacing: 6) {
            modeToggle
            chart()
            elevationReadout
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(ElevationDefaultTab.allCases) { tab in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = tab }
                } label: {
                    Text(tab.rawValue.capitalized)
                        .font(.system(size: 12, weight: mode == tab ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(mode == tab ? Color.green.opacity(0.25) : Color.clear)
                        .foregroundStyle(mode == tab ? .green : .secondary)
                }
                .buttonStyle(.plain)
            }
        }
        .background(Color.white.opacity(0.08), in: Capsule())
        .clipShape(Capsule())
    }

    @ViewBuilder
    private func chart() -> some View {
        let pts = activeSamples()
        if pts.isEmpty {
            Text("No elevation data in range")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
            let unitLabel = currentUnits.distance.label
            let domain = elevDomain(pts)
            let xMin = pts.first?.distanceFromStart ?? 0
            let xMax = pts.last?.distanceFromStart ?? 1
            let baseline = domain.lowerBound

            Chart {
                ForEach(Array(pts.enumerated()), id: \.offset) { _, pt in
                    elevationMarks(pt: pt, metersPerUnit: metersPerUnit, baseline: baseline)
                }

                if config.showGrade {
                    ForEach(Array(gradeSegments(pts: pts).enumerated()), id: \.offset) { _, seg in
                        RectangleMark(
                            xStart: .value("Start", seg.startMeters / metersPerUnit),
                            xEnd: .value("End", seg.endMeters / metersPerUnit),
                            yStart: .value("Base", baseline),
                            yEnd: .value("BandTop", baseline + (domain.upperBound - domain.lowerBound) * 0.06)
                        )
                        .foregroundStyle(seg.color.opacity(0.85))
                    }
                }

                // Waypoints render as full-height dashed orange rules so they're
                // visible without crowding the top of the chart.
                ForEach(Array(visiblePOIs.enumerated()), id: \.offset) { _, poi in
                    let x = poi.distanceFromStart / metersPerUnit
                    RuleMark(x: .value("POI", x))
                        .foregroundStyle(.orange.opacity(0.85))
                        .lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 2]))
                }

                RuleMark(x: .value("Now", currentDistance / metersPerUnit))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))

                PointMark(
                    x: .value("Now", currentDistance / metersPerUnit),
                    y: .value("Elev", convertElev(currentElevation))
                )
                .foregroundStyle(.white)
                .symbolSize(40)
            }
            .chartXScale(domain: (xMin / metersPerUnit)...(xMax / metersPerUnit))
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel(anchor: .topLeading) {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))\(unitLabel)")
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartYAxis {
                AxisMarks(position: .leading, values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
                        if let v = value.as(Double.self) {
                            Text("\(Int(v))\(currentUnits.elevation == .feet ? "ft" : "m")")
                                .font(.system(size: 8))
                        }
                    }
                }
            }
            .chartLegend(.hidden)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var elevationReadout: some View {
        HStack {
            Label(formatElevation(currentElevation), systemImage: "mountain.2")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
            Spacer()
            if config.showGainLossReadout, liveGain > 0 {
                Label(formatElevation(liveGain) + " gain", systemImage: "arrow.up.right")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Sample / POI filtering

    private func activeSamples() -> [ElevationSample] {
        guard !samples.isEmpty else { return [] }
        switch mode {
        case .full:
            return samples
        case .ahead:
            let end = currentDistance + config.aheadLookahead
            return samples.filter {
                $0.distanceFromStart >= currentDistance - 50 &&
                $0.distanceFromStart <= end
            }
        }
    }

    private var visiblePOIs: [RoutePOI] {
        guard showWaypoints, !pois.isEmpty else { return [] }
        switch mode {
        case .full:
            return pois
        case .ahead:
            let end = currentDistance + config.aheadLookahead
            return pois.filter { $0.distanceFromStart >= currentDistance && $0.distanceFromStart <= end }
        }
    }

    private func elevDomain(_ pts: [ElevationSample]) -> ClosedRange<Double> {
        let vals = pts.map { convertElev($0.elevation) }
        let lo = vals.min() ?? 0
        let hi = vals.max() ?? 100
        let pad = max((hi - lo) * 0.15, 5)
        return (lo - pad)...(hi + pad)
    }

    private func convertElev(_ meters: Double) -> Double {
        currentUnits.elevation == .feet ? meters * 3.28084 : meters
    }

    @ChartContentBuilder
    private func elevationMarks(pt: ElevationSample, metersPerUnit: Double, baseline: Double) -> some ChartContent {
        let x = pt.distanceFromStart / metersPerUnit
        let y = convertElev(pt.elevation)
        AreaMark(x: .value("Dist", x), yStart: .value("Base", baseline), yEnd: .value("Elev", y))
            .foregroundStyle(.linearGradient(
                colors: [Color.green.opacity(0.5), Color.green.opacity(0.05)],
                startPoint: .top, endPoint: .bottom
            ))
            .interpolationMethod(.catmullRom)
        LineMark(x: .value("Dist", x), y: .value("Elev", y))
            .foregroundStyle(.green)
            .interpolationMethod(.catmullRom)
            .lineStyle(StrokeStyle(lineWidth: 1.5))
    }

    private struct GradeSegment {
        let startMeters: Double
        let endMeters: Double
        let color: Color
    }

    private func gradeSegments(pts: [ElevationSample]) -> [GradeSegment] {
        guard pts.count >= 2 else { return [] }
        return zip(pts.dropLast(), pts.dropFirst()).map { a, b in
            let dx = b.distanceFromStart - a.distanceFromStart
            let dh = b.elevation - a.elevation
            let pct = dx > 0 ? dh / dx * 100.0 : 0
            return GradeSegment(
                startMeters: a.distanceFromStart,
                endMeters: b.distanceFromStart,
                color: gradeColor(pct)
            )
        }
    }

    private func gradeColor(_ pct: Double) -> Color {
        switch pct {
        case ..<(-3):     return .blue
        case ..<3:        return .green
        case ..<6:        return .yellow
        case ..<10:       return .orange
        default:          return .red
        }
    }
}

// MARK: - Mock data for previews

extension ElevationChart {
    /// Sampled profile from the bundled `Rob's Parks` simulated ride.
    /// Extracted offline from `SimulatedRides/Rob's Parks.gpx` so the phone
    /// preview matches what a real ride looks like on the watch.
    static let previewSamples: [ElevationSample] = [
        ElevationSample(distanceFromStart: 0,     elevation: 183.7),
        ElevationSample(distanceFromStart: 230,   elevation: 185.5),
        ElevationSample(distanceFromStart: 2951,  elevation: 180.3),
        ElevationSample(distanceFromStart: 3644,  elevation: 186.6),
        ElevationSample(distanceFromStart: 4805,  elevation: 181.9),
        ElevationSample(distanceFromStart: 6082,  elevation: 186.9),
        ElevationSample(distanceFromStart: 8628,  elevation: 186.1),
        ElevationSample(distanceFromStart: 9459,  elevation: 181.6),
        ElevationSample(distanceFromStart: 11662, elevation: 181.7),
        ElevationSample(distanceFromStart: 13486, elevation: 186.5),
        ElevationSample(distanceFromStart: 14545, elevation: 182.6),
        ElevationSample(distanceFromStart: 15693, elevation: 186.0),
        ElevationSample(distanceFromStart: 17039, elevation: 185.4),
        ElevationSample(distanceFromStart: 18449, elevation: 184.8),
        ElevationSample(distanceFromStart: 19525, elevation: 185.4),
        ElevationSample(distanceFromStart: 21901, elevation: 180.8),
        ElevationSample(distanceFromStart: 22835, elevation: 184.4),
        ElevationSample(distanceFromStart: 25358, elevation: 179.1),
        ElevationSample(distanceFromStart: 26585, elevation: 179.0),
        ElevationSample(distanceFromStart: 28456, elevation: 179.0),
        ElevationSample(distanceFromStart: 29661, elevation: 182.9),
        ElevationSample(distanceFromStart: 30513, elevation: 187.1),
        ElevationSample(distanceFromStart: 32881, elevation: 178.4),
        ElevationSample(distanceFromStart: 33780, elevation: 181.1),
        ElevationSample(distanceFromStart: 35818, elevation: 182.8),
        ElevationSample(distanceFromStart: 36869, elevation: 184.6),
        ElevationSample(distanceFromStart: 38602, elevation: 177.9),
        ElevationSample(distanceFromStart: 39206, elevation: 179.4),
        ElevationSample(distanceFromStart: 40666, elevation: 182.4),
        ElevationSample(distanceFromStart: 42433, elevation: 183.8),
        ElevationSample(distanceFromStart: 44907, elevation: 179.1),
        ElevationSample(distanceFromStart: 45300, elevation: 178.1),
        ElevationSample(distanceFromStart: 46879, elevation: 178.5),
        ElevationSample(distanceFromStart: 49080, elevation: 183.2),
        ElevationSample(distanceFromStart: 50726, elevation: 183.3),
        ElevationSample(distanceFromStart: 51240, elevation: 183.8),
        ElevationSample(distanceFromStart: 52684, elevation: 176.2),
        ElevationSample(distanceFromStart: 55286, elevation: 180.1),
        ElevationSample(distanceFromStart: 55997, elevation: 181.1),
        ElevationSample(distanceFromStart: 58360, elevation: 177.6),
        ElevationSample(distanceFromStart: 59207, elevation: 185.9),
        ElevationSample(distanceFromStart: 60089, elevation: 182.7),
        ElevationSample(distanceFromStart: 62382, elevation: 186.0),
        ElevationSample(distanceFromStart: 64460, elevation: 178.1),
        ElevationSample(distanceFromStart: 65517, elevation: 183.5),
        ElevationSample(distanceFromStart: 67135, elevation: 185.4),
        ElevationSample(distanceFromStart: 68326, elevation: 206.1),
        ElevationSample(distanceFromStart: 69910, elevation: 189.9),
        ElevationSample(distanceFromStart: 70577, elevation: 185.8),
    ]

    static let previewPOIs: [RoutePOI] = [
        RoutePOI(coordinate: .init(latitude: 0, longitude: 0),
                 name: "Water", description: nil,
                 distanceFromStart: 12_000, offRouteDistance: 0, nearestPointIndex: 0),
        RoutePOI(coordinate: .init(latitude: 0, longitude: 0),
                 name: "Lookout", description: nil,
                 distanceFromStart: 36_000, offRouteDistance: 0, nearestPointIndex: 0),
        RoutePOI(coordinate: .init(latitude: 0, longitude: 0),
                 name: "Cafe", description: nil,
                 distanceFromStart: 58_000, offRouteDistance: 0, nearestPointIndex: 0),
    ]

    /// Pretend the rider is ~32 km in so "Now" sits mid-route and the
    /// climb at the end is visible in "Ahead" mode if the lookahead is long
    /// enough.
    static let previewCurrentDistance: Double = 32_000
    static let previewCurrentElevation: Double = 181
    static let previewLiveGain: Double = 230
}
