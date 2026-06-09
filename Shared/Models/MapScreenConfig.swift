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
    case pink, red, orange, yellow, mint, cyan, blue, purple, white, brown

    var color: Color {
        switch self {
        case .pink: return .pink
        case .red: return .red
        case .orange: return .orange
        case .yellow: return .yellow
        case .mint: return .mint
        case .cyan: return .cyan
        case .blue: return .blue
        case .purple: return .purple
        case .white: return .white
        case .brown: return .brown
        }
    }

    var label: String { rawValue.capitalized }
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
    /// Starting zoom level in meters
    var defaultZoom: Double
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
        defaultZoom: 400,
        routeAheadColor: .white,
        showTurnOverlay: true,
        mapDetail: .off,
        waypointDisplay: .both
    )

    /// Compute 4 zoom levels geometrically spaced between min and max
    var computedZoomLevels: [Double] {
        guard zoomMax > zoomMin else { return [zoomMin] }
        let ratio = pow(zoomMax / zoomMin, 1.0 / 3.0)
        return (0..<4).map { zoomMin * pow(ratio, Double($0)) }
    }

    /// Index into computedZoomLevels closest to defaultZoom
    var defaultZoomIndex: Int {
        let levels = computedZoomLevels
        guard !levels.isEmpty else { return 0 }
        return levels.enumerated()
            .min(by: { abs($0.element - defaultZoom) < abs($1.element - defaultZoom) })?
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
        defaultZoom: Double = 400,
        routeAheadColor: RouteColor = .white,
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
        defaultZoom = try c.decodeIfPresent(Double.self, forKey: .defaultZoom) ?? 400
        routeAheadColor = try c.decodeIfPresent(RouteColor.self, forKey: .routeAheadColor) ?? .white
        showTurnOverlay = try c.decodeIfPresent(Bool.self, forKey: .showTurnOverlay) ?? true
        mapDetail = try c.decodeIfPresent(MapDetail.self, forKey: .mapDetail) ?? .off
        waypointDisplay = try c.decodeIfPresent(WaypointDisplay.self, forKey: .waypointDisplay) ?? .both
    }
}
