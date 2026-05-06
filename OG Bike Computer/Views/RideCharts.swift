//
//  RideCharts.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/10/26.
//

import SwiftUI
import Charts
import CoreLocation

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

    @State private var selected: RideChartMetric = .elevation

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
                .chartOverlay { proxy in
                    GeometryReader { geo in
                        Rectangle()
                            .fill(.clear)
                            .contentShape(Rectangle())
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { value in
                                        let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                        let metersPerUnit: Double = currentUnits.distance == .miles ? 1609.34 : 1000
                                        if let distInUnits: Double = proxy.value(atX: x) {
                                            let dist = distInUnits * metersPerUnit
                                            let maxDist = dataPoints.last?.distance ?? 0
                                            scrubDistance = max(0, min(dist, maxDist))
                                        }
                                    }
                                    .onEnded { _ in scrubDistance = nil }
                            )
                    }
                }

            toggleBar
            
            if let scrub = scrubDistance, let pt = closestPoint(to: scrub) {
                scrubReadout(pt)
            }
        }
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
        .padding(.vertical, 4)
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
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
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
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine(stroke: StrokeStyle(lineWidth: 0.3))
                AxisValueLabel {
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
                Rectangle()
                    .fill(.clear)
                    .contentShape(Rectangle())
                    .gesture(
                        DragGesture(minimumDistance: 0)
                            .onChanged { value in
                                let x = value.location.x - geo[proxy.plotFrame!].origin.x
                                if let distInUnits: Double = proxy.value(atX: x) {
                                    let dist = distInUnits * metersPerUnit
                                    let maxDistMeters = points.last?.distanceFromStart ?? 0
                                    scrubDistance = max(0, min(dist, maxDistMeters))
                                }
                            }
                            .onEnded { _ in scrubDistance = nil }
                    )
            }
        }

        if let scrub = scrubDistance, let elev = elevationAtDistance(scrub) {
            HStack(spacing: 16) {
                let metersPerUnit2: Double = currentUnits.distance == .miles ? 1609.34 : 1000
                Text(String(format: "%.1f %@", scrub / metersPerUnit2, currentUnits.distance.label))
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(.secondary)
                Text(formatElevation(elev))
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.green)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 4)
            .background(Color.green.opacity(0.1), in: Capsule())
        }
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
