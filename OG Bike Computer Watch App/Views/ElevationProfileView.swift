//
//  ElevationProfileView.swift
//  OG Bike Computer Watch App
//

import SwiftUI
import Charts

struct ElevationProfileView: View {
    @ObservedObject var workout: WorkoutManager

    private enum ViewMode: String, CaseIterable {
        case full = "Full"
        case ahead = "Ahead"
    }

    @State private var mode: ViewMode = .full
    @State private var initializedDefaultTab = false

    private var elevationConfig: ElevationScreenConfig {
        workout.ridePreferences.elevationScreen
    }

    private var lookaheadMeters: Double { elevationConfig.aheadLookahead }

    private var route: ProcessedRoute? { workout.navigation.processedRoute }
    private var currentDist: Double { workout.navigation.distanceAlongRoute }
    private var currentElev: Double { workout.currentElevation }

    /// Simplified elevation samples for cheap rendering. Falls back to nothing
    /// (handled by the empty-state branch) if the route didn't carry any.
    private var simplifiedSamples: [ElevationSample] {
        route?.simplifiedElevation ?? []
    }

    /// POIs the user opted to surface on the elevation screen.
    private var poisToShow: [RoutePOI] {
        guard workout.ridePreferences.mapScreen.waypointDisplay.showsOnElevation else { return [] }
        return route?.pois ?? []
    }

    var body: some View {
        if let route = route, !simplifiedSamples.isEmpty || route.points.contains(where: { $0.elevation != nil }) {
            VStack(spacing: 6) {
                modeToggle
                chart()
                elevationReadout
            }
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .safeAreaPadding(.top)
            .onAppear {
                guard !initializedDefaultTab else { return }
                initializedDefaultTab = true
                mode = elevationConfig.defaultTab == .ahead ? .ahead : .full
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mountain.2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No elevation data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var modeToggle: some View {
        HStack(spacing: 0) {
            ForEach(ViewMode.allCases, id: \.self) { m in
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) { mode = m }
                } label: {
                    Text(m.rawValue)
                        .font(.system(size: 12, weight: mode == m ? .semibold : .regular))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .background(mode == m ? Color.green.opacity(0.25) : Color.clear)
                        .foregroundStyle(mode == m ? .green : .secondary)
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

                // POI markers
                ForEach(Array(visiblePOIs.enumerated()), id: \.offset) { _, poi in
                    let x = poi.distanceFromStart / metersPerUnit
                    PointMark(
                        x: .value("POI", x),
                        y: .value("Top", domain.upperBound)
                    )
                    .symbol {
                        Image(systemName: "mappin")
                            .font(.system(size: 9))
                            .foregroundStyle(.orange)
                    }
                    .symbolSize(0)
                }

                // Current position marker
                RuleMark(x: .value("Now", currentDist / metersPerUnit))
                    .foregroundStyle(.white.opacity(0.7))
                    .lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 2]))

                PointMark(
                    x: .value("Now", currentDist / metersPerUnit),
                    y: .value("Elev", convertElev(currentElev))
                )
                .foregroundStyle(.white)
                .symbolSize(40)
            }
            .chartXScale(domain: (xMin / metersPerUnit)...(xMax / metersPerUnit))
            .chartYScale(domain: domain)
            .chartXAxis {
                AxisMarks(values: .automatic(desiredCount: 3)) { value in
                    AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                    AxisValueLabel {
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
            Label(formatElevation(currentElev), systemImage: "arrow.up.right")
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(.green)
            Spacer()
            if elevationConfig.showGainLossReadout, workout.liveElevationGain > 0 {
                Label(formatElevation(workout.liveElevationGain) + " gain", systemImage: "mountain.2")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Helpers

    /// Selects the simplified samples to render based on the active mode.
    private func activeSamples() -> [ElevationSample] {
        let samples = simplifiedSamples
        guard !samples.isEmpty else { return [] }
        switch mode {
        case .full:
            return samples
        case .ahead:
            let end = currentDist + lookaheadMeters
            return samples.filter {
                $0.distanceFromStart >= currentDist - 50 &&
                $0.distanceFromStart <= end
            }
        }
    }

    private var visiblePOIs: [RoutePOI] {
        let pois = poisToShow
        guard !pois.isEmpty else { return [] }
        switch mode {
        case .full:
            return pois
        case .ahead:
            let end = currentDist + lookaheadMeters
            return pois.filter { $0.distanceFromStart >= currentDist && $0.distanceFromStart <= end }
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
}
