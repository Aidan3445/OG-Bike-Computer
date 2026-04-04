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

    static let maxSecondaryStats = 4

    static let `default` = MapScreenConfig(
        primaryStat: .speed,
        secondaryStats: [.distance, .movingTime],
        showTurnInfo: true,
        showFullRouteToggle: true,
        showHeading: true,
        zoomMin: 200,
        zoomMax: 1600,
        defaultZoom: 400,
        routeAheadColor: .white,
        showTurnOverlay: true
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
        zoomMin: Double = 200,
        zoomMax: Double = 1600,
        defaultZoom: Double = 400,
        routeAheadColor: RouteColor = .white,
        showTurnOverlay: Bool = true
    ) {
        self.primaryStat = primaryStat
        self.secondaryStats = secondaryStats
        self.showTurnInfo = showTurnInfo
        self.showFullRouteToggle = showFullRouteToggle
        self.showHeading = showHeading
        self.zoomMin = zoomMin
        self.zoomMax = zoomMax
        self.defaultZoom = defaultZoom
        self.routeAheadColor = routeAheadColor
        self.showTurnOverlay = showTurnOverlay
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        primaryStat = try c.decodeIfPresent(MapStatType.self, forKey: .primaryStat) ?? .speed
        secondaryStats = try c.decodeIfPresent([MapStatType].self, forKey: .secondaryStats) ?? [.distance, .movingTime]
        showTurnInfo = try c.decodeIfPresent(Bool.self, forKey: .showTurnInfo) ?? true
        showFullRouteToggle = try c.decodeIfPresent(Bool.self, forKey: .showFullRouteToggle) ?? true
        showHeading = try c.decodeIfPresent(Bool.self, forKey: .showHeading) ?? true
        zoomMin = try c.decodeIfPresent(Double.self, forKey: .zoomMin) ?? 200
        zoomMax = try c.decodeIfPresent(Double.self, forKey: .zoomMax) ?? 1600
        defaultZoom = try c.decodeIfPresent(Double.self, forKey: .defaultZoom) ?? 400
        routeAheadColor = try c.decodeIfPresent(RouteColor.self, forKey: .routeAheadColor) ?? .white
        showTurnOverlay = try c.decodeIfPresent(Bool.self, forKey: .showTurnOverlay) ?? true
    }
}
