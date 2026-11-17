//
//  MapScreenConfig.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/3/26.
//

import Foundation
import SwiftUI

// MARK: - Map Stat Type

enum MapStatType: String, Codable, CaseIterable, Identifiable, Hashable {
    case speed
    case averageSpeed
    case heartRate
    case distance
    case movingTime
    case elapsedTime
    case elevation
    case grade
    case power
    case distanceRemaining
    case calories
    case none

    var id: String { rawValue }

    var label: String {
        switch self {
        case .speed: return "Speed"
        case .averageSpeed: return "Avg Speed"
        case .heartRate: return "Heart Rate"
        case .distance: return "Distance"
        case .movingTime: return "Moving Time"
        case .elapsedTime: return "Elapsed Time"
        case .elevation: return "Elevation"
        case .grade: return "Grade"
        case .power: return "Power"
        case .distanceRemaining: return "Remaining"
        case .calories: return "Calories"
        case .none: return "None"
        }
    }

    var icon: String {
        switch self {
        case .speed: return "speedometer"
        case .averageSpeed: return "gauge.with.dots.needle.50percent"
        case .heartRate: return "heart.fill"
        case .distance: return "road.lanes"
        case .movingTime: return "timer"
        case .elapsedTime: return "clock"
        case .elevation: return "mountain.2"
        case .grade: return "arrow.up.right"
        case .power: return "bolt.fill"
        case .distanceRemaining: return "flag.checkered"
        case .calories: return "flame.fill"
        case .none: return "minus"
        }
    }
}

// MARK: - Route Ahead Color

enum RouteColor: String, Codable, CaseIterable, Hashable {
    case pink, red, orange, yellow, mint, cyan, blue, indigo, purple, white, brown, rainbow

    /// Solid color for this choice. Rainbow has no single color, so renderers
    /// check for it and draw a gradient instead; red is only a stand-in.
    var color: Color {
        switch self {
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .mint: return .mint
        case .cyan: return .cyan
        case .blue: return .blue
        case .indigo: return .indigo
        case .purple: return .purple
        case .white: return .white
        case .brown: return .brown
        case .rainbow: return .red
        }
    }

    var label: String { rawValue.capitalized }
}

// MARK: - Zoom Steps

/// Zoom distances that read as round numbers in the rider's units. The ride
/// zoom levels and the default zoom slider pick from these instead of dividing
/// the range evenly, so every stop gets a clean label. Feet and miles use the
/// same conversions as the zoom labels so whole values format cleanly.
enum ZoomSteps {
    private nonisolated static func feet(_ ft: Double) -> Double { ft / 3.28084 }
    private nonisolated static func miles(_ mi: Double) -> Double { mi * 1609.34 }

    private static var isImperial: Bool { currentUnits.distance == .miles }

    static var closestOptions: [Double] {
        isImperial ? [300, 500, 750, 1000, 1250].map(feet) : [100, 150, 200, 300, 400]
    }

    static var farthestOptions: [Double] {
        isImperial ? [0.5, 0.75, 1, 1.5, 2].map(miles) : [800, 1200, 1600, 2400, 3200]
    }

    /// Round distances from the smallest closest option to the largest
    /// farthest option. The ends of the user's range are always added on top.
    static var candidates: [Double] {
        isImperial
            ? [300, 400, 500, 650, 750, 1000, 1200, 1500, 1750, 2000].map(feet) + [0.5, 0.75, 1, 1.25, 1.5, 1.75, 2].map(miles)
            : [100, 150, 200, 250, 300, 400, 500, 600, 800, 1000, 1200, 1500, 2000, 2500, 3000]
    }

    /// Zoom distance label. Miles and kilometers get one decimal, or two for
    /// quarter values like 0.25 and 0.75; feet and meters are whole numbers.
    static func label(_ meters: Double) -> String {
        if isImperial {
            let feet = meters * 3.28084
            if feet >= 2639.5 { // 0.5 miles, with room for conversion rounding
                let miles = meters / 1609.34
                if miles == Double(Int(miles)) {
                    return "\(Int(miles)) mi"
                }
                if 75 == Int(miles * 100) % 100 || 25 == Int(miles * 100) % 100 {
                    return String(format: "%.2f mi", miles)
                }
                return String(format: "%.1f mi", miles)
            }
            return "\(Int(round(feet))) ft"
        }
        if meters >= 1000 {
            let km = meters / 1000
            if km == Double(Int(km)) {
                return "\(Int(km)) km"
            }
            if 75 == Int(km * 100) % 100 || 25 == Int(km * 100) % 100 {
                return String(format: "%.2f km", km)
            }
            return String(format: "%.1f km", km)
        }
        return "\(Int(meters))m"
    }

    static func snap(_ value: Double, to options: [Double]) -> Double {
        options.min(by: { abs($0 - value) < abs($1 - value) }) ?? value
    }

    /// How far any in-between zoom must sit from the closest and farthest
    /// zoom: 10% of the range, rounded up to 50 ft (or 25 m). That keeps a
    /// real jump between an end and the level next to it.
    static func minimumGap(closest: Double, farthest: Double) -> Double {
        let unit = isImperial ? feet(50) : 25
        return ((farthest - closest) * 0.1 / unit).rounded(.up) * unit
    }

    /// Default zoom slider stops: the two ends plus up to 8 round distances
    /// between them, picked evenly through the list (so evenly by position in
    /// the list, not by distance).
    static func defaultZoomStops(closest: Double, farthest: Double, count: Int = 10) -> [Double] {
        guard farthest > closest else { return [closest] }
        let gap = minimumGap(closest: closest, farthest: farthest)
        let inside = candidates.filter { $0 >= closest + gap - 0.5 && $0 <= farthest - gap + 0.5 }
        return [closest] + spread(inside, count: count - 2) + [farthest]
    }

    /// The four ride zoom levels. The ends and the default are fixed, and the
    /// rest are round distances placed where an even zoom ratio would put
    /// them, each at least the minimum gap from its neighbors.
    static func zoomLevels(closest: Double, farthest: Double, defaultZoom: Double) -> [Double] {
        guard farthest > closest else { return [closest] }
        let gap = minimumGap(closest: closest, farthest: farthest)
        let def = min(max(defaultZoom, closest), farthest)
        let defaultIsEnd = def - closest < 1 || farthest - def < 1

        func nearest(to ideal: Double, between lo: Double, and hi: Double, avoiding taken: [Double]) -> Double? {
            candidates
                .filter { $0 >= lo + gap - 0.5 && $0 <= hi - gap + 0.5 }
                .filter { c in taken.allSatisfy { abs($0 - c) >= gap - 0.5 } }
                .min(by: { abs(log($0 / ideal)) < abs(log($1 / ideal)) })
        }

        if defaultIsEnd {
            // Two levels between the ends, at even thirds of the zoom ratio.
            let ratio = farthest / closest
            let lowIdeal = closest * pow(ratio, 1.0 / 3.0)
            let highIdeal = closest * pow(ratio, 2.0 / 3.0)
            let low = nearest(to: lowIdeal, between: closest, and: farthest, avoiding: []) ?? lowIdeal
            let high = nearest(to: highIdeal, between: closest, and: farthest, avoiding: [low]) ?? highIdeal
            return [closest, low, high, farthest].sorted()
        }

        // One more level in whichever side of the default is the bigger
        // zoom jump, falling back to the other side if nothing fits.
        let sides = [(closest, def), (def, farthest)].sorted { $0.1 / $0.0 > $1.1 / $1.0 }
        let extra = sides.lazy
            .compactMap { lo, hi in nearest(to: sqrt(lo * hi), between: lo, and: hi, avoiding: []) }
            .first ?? sqrt(sides[0].0 * sides[0].1)
        return [closest, def, extra, farthest].sorted()
    }

    /// `count` items spread evenly through `list` by position, keeping all of
    /// them when there aren't more than `count`.
    private static func spread(_ list: [Double], count: Int) -> [Double] {
        guard list.count > count, count > 0 else { return count > 0 ? list : [] }
        if count == 1 { return [list[list.count / 2]] }
        return (0..<count).map { i in
            list[Int((Double(i) * Double(list.count - 1) / Double(count - 1)).rounded())]
        }
    }
}

// MARK: - Map Detail Level

enum MapDetail: String, Codable, CaseIterable, Identifiable, Hashable {
    case off
    case on

    var id: String { rawValue }

    var label: String {
        switch self {
        case .off: return "Off"
        case .on: return "On"
        }
    }

    var batteryImpact: String {
        switch self {
        case .off: return "Least demanding"
        case .on: return "Most demanding"
        }
    }
}

// MARK: - Waypoint Display

/// Where on the watch to render route POIs / waypoints.
enum WaypointDisplay: String, Codable, CaseIterable, Hashable, Identifiable {
    case none, routeMap, elevation, both
    var id: String { rawValue }

    var label: String {
        switch self {
        case .none:     return "Hidden"
        case .routeMap: return "Route Map"
        case .elevation: return "Elevation"
        case .both:     return "Both"
        }
    }

    var showsOnRouteMap: Bool { self == .routeMap || self == .both }
    var showsOnElevation: Bool { self == .elevation || self == .both }
}

// MARK: - Elevation Screen Config

/// Which tab the watch elevation screen opens to by default.
enum ElevationDefaultTab: String, Codable, CaseIterable, Hashable, Identifiable {
    case full, ahead
    var id: String { rawValue }

    var label: String {
        switch self {
        case .full:  return "Full Route"
        case .ahead: return "Ahead"
        }
    }
}

struct ElevationScreenConfig: Codable, Equatable, Hashable {
    /// Whether to include the elevation screen as a watch tab at all.
    var enabled: Bool
    /// Default tab when entering the screen.
    var defaultTab: ElevationDefaultTab
    /// How far ahead the "Ahead" view looks, in meters.
    var aheadLookahead: Double
    /// Show grade overlay underneath the elevation line.
    var showGrade: Bool
    /// Show total ride elevation gain/loss next to the chart.
    var showGainLossReadout: Bool

    static let `default` = ElevationScreenConfig(
        enabled: true,
        defaultTab: .full,
        aheadLookahead: 8046.72, // 5 miles
        showGrade: false,
        showGainLossReadout: true
    )

    init(
        enabled: Bool = true,
        defaultTab: ElevationDefaultTab = .full,
        aheadLookahead: Double = 8046.72,
        showGrade: Bool = false,
        showGainLossReadout: Bool = true
    ) {
        self.enabled = enabled
        self.defaultTab = defaultTab
        self.aheadLookahead = aheadLookahead
        self.showGrade = showGrade
        self.showGainLossReadout = showGainLossReadout
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        defaultTab = try c.decodeIfPresent(ElevationDefaultTab.self, forKey: .defaultTab) ?? .full
        aheadLookahead = try c.decodeIfPresent(Double.self, forKey: .aheadLookahead) ?? 8046.72
        showGrade = try c.decodeIfPresent(Bool.self, forKey: .showGrade) ?? false
        showGainLossReadout = try c.decodeIfPresent(Bool.self, forKey: .showGainLossReadout) ?? true
    }
}

// MARK: - Map Screen Config

struct MapScreenConfig: Codable, Equatable, Hashable {
    /// Large stat displayed at the top of the overlay
    var primaryStat: MapStatType
    /// Smaller stats displayed below the primary stat (max 4)
    var secondaryStats: [MapStatType]
    /// Show turn direction + distance in the overlay
    var showTurnInfo: Bool
    /// Show the full route / breadcrumb toggle button
    var showFullRouteToggle: Bool
    /// Show cardinal direction indicator
    var showHeading: Bool
    /// Show the "repeat upcoming turn alert" button (waveform icon) on the
    /// map screen. Defaults true — a rider can quickly silence/restore it
    /// from the customization screen.
    var showRepeatAlertButton: Bool
    /// Closest zoom level in meters (most zoomed in)
    var zoomMin: Double
    /// Farthest zoom level in meters (most zoomed out)
    var zoomMax: Double
    /// Starting zoom level in meters. Nil means the middle slider stop, so a
    /// fresh setup lands in the middle in either unit system.
    var defaultZoom: Double?
    /// Color of the route ahead line
    var routeAheadColor: RouteColor
    /// Show map overlay on metric screens when turns approach
    var showTurnOverlay: Bool
    /// MapKit background detail level (off = black background, on = full map tiles)
    var mapDetail: MapDetail
    /// Where to render route POIs / waypoints on watch screens.
    var waypointDisplay: WaypointDisplay

    static let maxSecondaryStats = 4

    static let `default` = MapScreenConfig(
        primaryStat: .speed,
        secondaryStats: [.distance, .movingTime],
        showTurnInfo: true,
        showFullRouteToggle: true,
        showHeading: true,
        showRepeatAlertButton: true,
        zoomMin: 200,
        zoomMax: 1600,
        defaultZoom: nil,
        routeAheadColor: .rainbow,
        showTurnOverlay: true,
        mapDetail: .off,
        waypointDisplay: .both
    )

    /// Closest zoom snapped to the option Settings shows, so a value saved in
    /// the other unit system (or an old default) still lands on a round number.
    var effectiveZoomMin: Double { ZoomSteps.snap(zoomMin, to: ZoomSteps.closestOptions) }
    /// Farthest zoom, snapped the same way.
    var effectiveZoomMax: Double { ZoomSteps.snap(zoomMax, to: ZoomSteps.farthestOptions) }

    /// The default zoom slider's stops for the current range.
    var defaultZoomStops: [Double] {
        ZoomSteps.defaultZoomStops(closest: effectiveZoomMin, farthest: effectiveZoomMax)
    }
    /// Default zoom snapped to the nearest slider stop, so it stays valid when
    /// the range or units change.
    var effectiveDefaultZoom: Double {
        let stops = defaultZoomStops
        guard let defaultZoom else { return stops[stops.count / 2] }
        return ZoomSteps.snap(defaultZoom, to: stops)
    }

    /// The four ride zoom levels: closest, farthest, default, and round
    /// distances filling the rest.
    var computedZoomLevels: [Double] {
        ZoomSteps.zoomLevels(closest: effectiveZoomMin, farthest: effectiveZoomMax, defaultZoom: effectiveDefaultZoom)
    }

    /// Index into computedZoomLevels closest to the default zoom
    var defaultZoomIndex: Int {
        let levels = computedZoomLevels
        let target = effectiveDefaultZoom
        guard !levels.isEmpty else { return 0 }
        return levels.enumerated()
            .min(by: { abs($0.element - target) < abs($1.element - target) })?
            .offset ?? 0
    }

    init(
        primaryStat: MapStatType = .speed,
        secondaryStats: [MapStatType] = [.distance, .movingTime],
        showTurnInfo: Bool = true,
        showFullRouteToggle: Bool = true,
        showHeading: Bool = true,
        showRepeatAlertButton: Bool = true,
        zoomMin: Double = 200,
        zoomMax: Double = 1600,
        defaultZoom: Double? = nil,
        routeAheadColor: RouteColor = .rainbow,
        showTurnOverlay: Bool = true,
        mapDetail: MapDetail = .off,
        waypointDisplay: WaypointDisplay = .both
    ) {
        self.primaryStat = primaryStat
        self.secondaryStats = secondaryStats
        self.showTurnInfo = showTurnInfo
        self.showFullRouteToggle = showFullRouteToggle
        self.showHeading = showHeading
        self.showRepeatAlertButton = showRepeatAlertButton
        self.zoomMin = zoomMin
        self.zoomMax = zoomMax
        self.defaultZoom = defaultZoom
        self.routeAheadColor = routeAheadColor
        self.showTurnOverlay = showTurnOverlay
        self.mapDetail = mapDetail
        self.waypointDisplay = waypointDisplay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryStat = try c.decodeIfPresent(MapStatType.self, forKey: .primaryStat) ?? .speed
        secondaryStats = try c.decodeIfPresent([MapStatType].self, forKey: .secondaryStats) ?? [.distance, .movingTime]
        showTurnInfo = try c.decodeIfPresent(Bool.self, forKey: .showTurnInfo) ?? true
        showFullRouteToggle = try c.decodeIfPresent(Bool.self, forKey: .showFullRouteToggle) ?? true
        showHeading = try c.decodeIfPresent(Bool.self, forKey: .showHeading) ?? true
        showRepeatAlertButton = try c.decodeIfPresent(Bool.self, forKey: .showRepeatAlertButton) ?? true
        zoomMin = try c.decodeIfPresent(Double.self, forKey: .zoomMin) ?? 200
        zoomMax = try c.decodeIfPresent(Double.self, forKey: .zoomMax) ?? 1600
        defaultZoom = try c.decodeIfPresent(Double.self, forKey: .defaultZoom)
        routeAheadColor = try c.decodeIfPresent(RouteColor.self, forKey: .routeAheadColor) ?? .rainbow
        showTurnOverlay = try c.decodeIfPresent(Bool.self, forKey: .showTurnOverlay) ?? true
        mapDetail = try c.decodeIfPresent(MapDetail.self, forKey: .mapDetail) ?? .off
        waypointDisplay = try c.decodeIfPresent(WaypointDisplay.self, forKey: .waypointDisplay) ?? .both
    }
}
