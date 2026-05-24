//
//  RidePreferences.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import Foundation

// MARK: - GPS Accuracy Floor

enum GPSAccuracyFloor: String, Codable, CaseIterable, Hashable {
    case best
    case balanced
    case powerSaver

    var label: String {
        switch self {
        case .best: return "Best"
        case .balanced: return "Balanced"
        case .powerSaver: return "Power Saver"
        }
    }

    var batteryImpact: String {
        switch self {
        case .best: return "Most demanding"
        case .balanced: return "Moderate"
        case .powerSaver: return "Least demanding"
        }
    }
}

// MARK: - Elevation Smoothing

enum ElevationSmoothing: String, Codable, CaseIterable, Hashable {
    case off, light, moderate, heavy

    var label: String {
        switch self {
        case .off: return "Off"
        case .light: return "Light"
        case .moderate: return "Moderate"
        case .heavy: return "Heavy"
        }
    }

    var elevMinDelta: Double {
        switch self {
        case .off: return 0.0
        case .light: return 1.0
        case .moderate: return 2.0
        case .heavy: return 3.0
        }
    }

    var gradeWindowDistance: Double {
        switch self {
        case .off: return 50
        case .light: return 40
        case .moderate: return 50
        case .heavy: return 75
        }
    }

    var routeGradeAlpha: Double {
        switch self {
        case .off: return 0.5
        case .light: return 0.4
        case .moderate: return 0.3
        case .heavy: return 0.2
        }
    }

    var gpsGradeAlpha: Double {
        switch self {
        case .off: return 0.5
        case .light: return 0.5
        case .moderate: return 0.4
        case .heavy: return 0.3
        }
    }
}

// MARK: - Map Rotation

enum MapRotation: String, Codable, CaseIterable, Hashable {
    case headingUp, northUp

    var label: String {
        switch self {
        case .headingUp: return "Heading Up"
        case .northUp: return "North Up"
        }
    }
}

// MARK: - Ride Privacy

enum RidePrivacy: String, Codable, CaseIterable, Hashable {
    case off, trimStartEnd

    var label: String {
        switch self {
        case .off: return "Off"
        case .trimStartEnd: return "Trim Start & End"
        }
    }

    var trimDistance: Double {
        switch self {
        case .off: return 0
        case .trimStartEnd: return 200
        }
    }
}

// MARK: - Auto-Pause Preferences

struct AutoPausePreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var speedThreshold: Double // m/s

    static let `default` = AutoPausePreferences(
        enabled: true,
        speedThreshold: 0.894 // ~2 mph
    )

    init(enabled: Bool = true, speedThreshold: Double = 0.894) {
        self.enabled = enabled
        self.speedThreshold = speedThreshold
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        speedThreshold = try c.decodeIfPresent(Double.self, forKey: .speedThreshold) ?? 0.894
    }
}

// MARK: - Auto-Lap Preferences

struct AutoLapPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var lapDistance: Double // meters
    var mode: AlertMode

    static let `default` = AutoLapPreferences(
        enabled: false,
        lapDistance: 1609.34, // 1 mile
        mode: .voiceOnly
    )

    init(enabled: Bool = false, lapDistance: Double = 1609.34, mode: AlertMode = .voiceOnly) {
        self.enabled = enabled
        self.lapDistance = lapDistance
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        lapDistance = try c.decodeIfPresent(Double.self, forKey: .lapDistance) ?? 1609.34
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceOnly
    }
}

// MARK: - Telemetry Rate

enum TelemetryRate: String, Codable, CaseIterable, Hashable {
    case fast       // 1 second — most responsive Live Activity
    case standard   // 3 seconds — balanced (default)
    case battery    // 5 seconds — maximum battery savings

    var interval: TimeInterval {
        switch self {
        case .fast: return 1.0
        case .standard: return 3.0
        case .battery: return 5.0
        }
    }

    var label: String {
        switch self {
        case .fast: return "Fast (1s)"
        case .standard: return "Standard (3s)"
        case .battery: return "Battery Saver (5s)"
        }
    }

    var batteryImpact: String {
        switch self {
        case .fast: return "Most demanding"
        case .standard: return "Moderate"
        case .battery: return "Least demanding"
        }
    }
}

// MARK: - Checkpoint Interval

enum CheckpointInterval: String, Codable, CaseIterable, Hashable {
    case disabled, fiveMin, tenMin, fifteenMin, thirtyMin

    var interval: TimeInterval? {
        switch self {
        case .disabled:   return nil
        case .fiveMin:    return 5 * 60
        case .tenMin:     return 10 * 60
        case .fifteenMin: return 15 * 60
        case .thirtyMin:  return 30 * 60
        }
    }

    var label: String {
        switch self {
        case .disabled:   return "Disabled"
        case .fiveMin:    return "Every 5 min"
        case .tenMin:     return "Every 10 min"
        case .fifteenMin: return "Every 15 min"
        case .thirtyMin:  return "Every 30 min"
        }
    }
}

// MARK: - Tab Order

/// One of the watch's main workout tabs. Metric pages are referenced by their
/// MetricPage UUID; the two built-ins use sentinel values.
struct WorkoutTabKey: Codable, Equatable, Hashable, Identifiable {
    enum Kind: String, Codable {
        case routeMap
        case elevation
        case metricPage
    }

    let kind: Kind
    /// Only set when `kind == .metricPage` — the MetricPage's UUID.
    let metricPageID: UUID?

    var id: String {
        switch kind {
        case .routeMap:    return "routeMap"
        case .elevation:   return "elevation"
        case .metricPage:  return "metric:\(metricPageID?.uuidString ?? "?")"
        }
    }

    static let routeMap = WorkoutTabKey(kind: .routeMap, metricPageID: nil)
    static let elevation = WorkoutTabKey(kind: .elevation, metricPageID: nil)
    static func metricPage(_ id: UUID) -> WorkoutTabKey {
        WorkoutTabKey(kind: .metricPage, metricPageID: id)
    }
}

// MARK: - Top-Level Ride Preferences

struct RidePreferences: Codable, Equatable, Hashable {
    var autoPause: AutoPausePreferences
    var autoLap: AutoLapPreferences
    var gpsAccuracyFloor: GPSAccuracyFloor
    var elevationSmoothing: ElevationSmoothing
    var mapRotation: MapRotation
    var wakeOnAlert: Bool
    var ridePrivacy: RidePrivacy
    var dynamicGPSOptimization: Bool
    var telemetryRate: TelemetryRate
    var offRouteGraceSamples: Int
    var mapScreen: MapScreenConfig
    var elevationScreen: ElevationScreenConfig
    var checkpointInterval: CheckpointInterval
    /// Custom workout tab order (when nil, default order applies). Stores stable
    /// keys so metric pages keep their slot when added/removed.
    var tabOrder: [WorkoutTabKey]?

    static let `default` = RidePreferences(
        autoPause: .default,
        autoLap: .default,
        gpsAccuracyFloor: .best,
        elevationSmoothing: .moderate,
        mapRotation: .headingUp,
        wakeOnAlert: true,
        ridePrivacy: .off,
        dynamicGPSOptimization: true,
        telemetryRate: .standard,
        offRouteGraceSamples: 3,
        mapScreen: .default,
        elevationScreen: .default,
        checkpointInterval: .tenMin,
        tabOrder: nil
    )

    init(
        autoPause: AutoPausePreferences = .default,
        autoLap: AutoLapPreferences = .default,
        gpsAccuracyFloor: GPSAccuracyFloor = .best,
        elevationSmoothing: ElevationSmoothing = .moderate,
        mapRotation: MapRotation = .headingUp,
        wakeOnAlert: Bool = true,
        ridePrivacy: RidePrivacy = .off,
        dynamicGPSOptimization: Bool = true,
        telemetryRate: TelemetryRate = .standard,
        offRouteGraceSamples: Int = 3,
        mapScreen: MapScreenConfig = .default,
        elevationScreen: ElevationScreenConfig = .default,
        checkpointInterval: CheckpointInterval = .tenMin,
        tabOrder: [WorkoutTabKey]? = nil
    ) {
        self.autoPause = autoPause
        self.autoLap = autoLap
        self.gpsAccuracyFloor = gpsAccuracyFloor
        self.elevationSmoothing = elevationSmoothing
        self.mapRotation = mapRotation
        self.wakeOnAlert = wakeOnAlert
        self.ridePrivacy = ridePrivacy
        self.dynamicGPSOptimization = dynamicGPSOptimization
        self.telemetryRate = telemetryRate
        self.offRouteGraceSamples = offRouteGraceSamples
        self.mapScreen = mapScreen
        self.elevationScreen = elevationScreen
        self.checkpointInterval = checkpointInterval
        self.tabOrder = tabOrder
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        autoPause = try c.decodeIfPresent(AutoPausePreferences.self, forKey: .autoPause) ?? .default
        autoLap = try c.decodeIfPresent(AutoLapPreferences.self, forKey: .autoLap) ?? .default
        gpsAccuracyFloor = try c.decodeIfPresent(GPSAccuracyFloor.self, forKey: .gpsAccuracyFloor) ?? .best
        elevationSmoothing = try c.decodeIfPresent(ElevationSmoothing.self, forKey: .elevationSmoothing) ?? .moderate
        mapRotation = try c.decodeIfPresent(MapRotation.self, forKey: .mapRotation) ?? .headingUp
        wakeOnAlert = try c.decodeIfPresent(Bool.self, forKey: .wakeOnAlert) ?? true
        ridePrivacy = try c.decodeIfPresent(RidePrivacy.self, forKey: .ridePrivacy) ?? .off
        dynamicGPSOptimization = try c.decodeIfPresent(Bool.self, forKey: .dynamicGPSOptimization) ?? true
        telemetryRate = try c.decodeIfPresent(TelemetryRate.self, forKey: .telemetryRate) ?? .standard
        offRouteGraceSamples = try c.decodeIfPresent(Int.self, forKey: .offRouteGraceSamples) ?? 3
        mapScreen = try c.decodeIfPresent(MapScreenConfig.self, forKey: .mapScreen) ?? .default
        elevationScreen = try c.decodeIfPresent(ElevationScreenConfig.self, forKey: .elevationScreen) ?? .default
        checkpointInterval = try c.decodeIfPresent(CheckpointInterval.self, forKey: .checkpointInterval) ?? .tenMin
        tabOrder = try c.decodeIfPresent([WorkoutTabKey].self, forKey: .tabOrder)
    }
}
