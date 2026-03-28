//
//  NavigationAlertPreferences.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import Foundation

// MARK: - Alert Mode

enum AlertMode: String, Codable, CaseIterable, Hashable {
    case voiceAndHaptic
    case voiceOnly
    case hapticOnly
    case none

    var label: String {
        switch self {
        case .voiceAndHaptic: return "Voice & Buzz"
        case .voiceOnly: return "Voice"
        case .hapticOnly: return "Buzz"
        case .none: return "None"
        }
    }

    var shortLabel: String {
        switch self {
        case .voiceAndHaptic: return "Both"
        case .voiceOnly: return "Voice"
        case .hapticOnly: return "Buzz"
        case .none: return "None"
        }
    }

    var includesVoice: Bool {
        self == .voiceAndHaptic || self == .voiceOnly
    }

    var includesHaptic: Bool {
        self == .voiceAndHaptic || self == .hapticOnly
    }
}

// MARK: - Haptic Intensity

enum HapticIntensity: String, Codable, CaseIterable, Hashable {
    case light, medium, strong

    var label: String {
        switch self {
        case .light: return "Light"
        case .medium: return "Medium"
        case .strong: return "Strong"
        }
    }
}

// MARK: - Turn Alert Preferences

struct TurnAlertPreferences: Codable, Equatable, Hashable {
    var defaultMode: AlertMode
    var primaryApproachDistance: Double   // meters
    var secondaryApproachEnabled: Bool
    var secondaryApproachDistance: Double // meters
    var atTurnMode: AlertMode?           // nil = use defaultMode
    var primaryApproachMode: AlertMode?  // nil = use defaultMode
    var secondaryApproachMode: AlertMode? // nil = use defaultMode

    static let `default` = TurnAlertPreferences(
        defaultMode: .voiceAndHaptic,
        primaryApproachDistance: 121.92,  // 400ft
        secondaryApproachEnabled: false,
        secondaryApproachDistance: 804.672, // 0.5mi
        atTurnMode: nil,
        primaryApproachMode: nil,
        secondaryApproachMode: nil
    )

    func resolvedAtTurnMode() -> AlertMode {
        atTurnMode ?? defaultMode
    }

    func resolvedPrimaryApproachMode() -> AlertMode {
        primaryApproachMode ?? defaultMode
    }

    func resolvedSecondaryApproachMode() -> AlertMode {
        secondaryApproachMode ?? defaultMode
    }

    /// Build the alert distances array for VoiceNavigator
    var alertDistances: [Double] {
        var distances: [Double] = []
        if secondaryApproachEnabled {
            distances.append(secondaryApproachDistance)
        }
        distances.append(primaryApproachDistance)
        distances.append(0) // at turn
        return distances
    }

    /// Resolve the mode for a given alert distance index
    func mode(forAlertIndex index: Int, totalCount: Int) -> AlertMode {
        // Last index is always "at turn"
        if index == totalCount - 1 {
            return resolvedAtTurnMode()
        }
        // Second-to-last is primary approach
        if index == totalCount - 2 {
            return resolvedPrimaryApproachMode()
        }
        // Anything before that is secondary approach
        return resolvedSecondaryApproachMode()
    }

    init(
        defaultMode: AlertMode = .voiceAndHaptic,
        primaryApproachDistance: Double = 121.92,
        secondaryApproachEnabled: Bool = false,
        secondaryApproachDistance: Double = 804.672,
        atTurnMode: AlertMode? = nil,
        primaryApproachMode: AlertMode? = nil,
        secondaryApproachMode: AlertMode? = nil
    ) {
        self.defaultMode = defaultMode
        self.primaryApproachDistance = primaryApproachDistance
        self.secondaryApproachEnabled = secondaryApproachEnabled
        self.secondaryApproachDistance = secondaryApproachDistance
        self.atTurnMode = atTurnMode
        self.primaryApproachMode = primaryApproachMode
        self.secondaryApproachMode = secondaryApproachMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        defaultMode = try c.decodeIfPresent(AlertMode.self, forKey: .defaultMode) ?? .voiceAndHaptic
        primaryApproachDistance = try c.decodeIfPresent(Double.self, forKey: .primaryApproachDistance) ?? 121.92
        secondaryApproachEnabled = try c.decodeIfPresent(Bool.self, forKey: .secondaryApproachEnabled) ?? false
        secondaryApproachDistance = try c.decodeIfPresent(Double.self, forKey: .secondaryApproachDistance) ?? 804.672
        atTurnMode = try c.decodeIfPresent(AlertMode.self, forKey: .atTurnMode)
        primaryApproachMode = try c.decodeIfPresent(AlertMode.self, forKey: .primaryApproachMode)
        secondaryApproachMode = try c.decodeIfPresent(AlertMode.self, forKey: .secondaryApproachMode)
    }
}

// MARK: - Navigation Event Preferences

struct NavigationEventPreferences: Codable, Equatable, Hashable {
    var halfwayAlert: AlertMode
    var offRouteAlert: AlertMode
    var offRouteThreshold: Double // meters
    var backOnRouteAlert: AlertMode
    var arrivalAlert: AlertMode

    static let `default` = NavigationEventPreferences(
        halfwayAlert: .voiceAndHaptic,
        offRouteAlert: .voiceAndHaptic,
        offRouteThreshold: 100,
        backOnRouteAlert: .voiceAndHaptic,
        arrivalAlert: .voiceAndHaptic
    )

    init(
        halfwayAlert: AlertMode = .voiceAndHaptic,
        offRouteAlert: AlertMode = .voiceAndHaptic,
        offRouteThreshold: Double = 100,
        backOnRouteAlert: AlertMode = .voiceAndHaptic,
        arrivalAlert: AlertMode = .voiceAndHaptic
    ) {
        self.halfwayAlert = halfwayAlert
        self.offRouteAlert = offRouteAlert
        self.offRouteThreshold = offRouteThreshold
        self.backOnRouteAlert = backOnRouteAlert
        self.arrivalAlert = arrivalAlert
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        halfwayAlert = try c.decodeIfPresent(AlertMode.self, forKey: .halfwayAlert) ?? .voiceAndHaptic
        offRouteAlert = try c.decodeIfPresent(AlertMode.self, forKey: .offRouteAlert) ?? .voiceAndHaptic
        offRouteThreshold = try c.decodeIfPresent(Double.self, forKey: .offRouteThreshold) ?? 100
        backOnRouteAlert = try c.decodeIfPresent(AlertMode.self, forKey: .backOnRouteAlert) ?? .voiceAndHaptic
        arrivalAlert = try c.decodeIfPresent(AlertMode.self, forKey: .arrivalAlert) ?? .voiceAndHaptic
    }
}

// MARK: - Split Alert Preferences

struct SplitAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var splitDistance: Double // meters
    var selectedMetrics: [MetricType]
    var mode: AlertMode

    static let `default` = SplitAlertPreferences(
        enabled: false,
        splitDistance: 1609.34, // 1 mile
        selectedMetrics: [.movingTime, .averageSpeed, .maxSpeed],
        mode: .voiceOnly
    )

    init(
        enabled: Bool = false,
        splitDistance: Double = 1609.34,
        selectedMetrics: [MetricType] = [.movingTime, .averageSpeed, .maxSpeed],
        mode: AlertMode = .voiceOnly
    ) {
        self.enabled = enabled
        self.splitDistance = splitDistance
        self.selectedMetrics = selectedMetrics
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        splitDistance = try c.decodeIfPresent(Double.self, forKey: .splitDistance) ?? 1609.34
        selectedMetrics = try c.decodeIfPresent([MetricType].self, forKey: .selectedMetrics) ?? [.movingTime, .averageSpeed, .maxSpeed]
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceOnly
    }
}

// MARK: - Auto-Pause Alert Preferences

struct AutoPauseAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var pauseMode: AlertMode
    var resumeMode: AlertMode

    static let `default` = AutoPauseAlertPreferences(
        enabled: false,
        pauseMode: .voiceAndHaptic,
        resumeMode: .voiceAndHaptic
    )

    init(
        enabled: Bool = false,
        pauseMode: AlertMode = .voiceAndHaptic,
        resumeMode: AlertMode = .voiceAndHaptic
    ) {
        self.enabled = enabled
        self.pauseMode = pauseMode
        self.resumeMode = resumeMode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        pauseMode = try c.decodeIfPresent(AlertMode.self, forKey: .pauseMode) ?? .voiceAndHaptic
        resumeMode = try c.decodeIfPresent(AlertMode.self, forKey: .resumeMode) ?? .voiceAndHaptic
    }
}

// MARK: - Descent Alert Preferences

struct DescentAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var speedThreshold: Double          // m/s (default 13.41 ≈ 30mph)
    var minimumDescentDistance: Double   // meters
    var mode: AlertMode

    static let `default` = DescentAlertPreferences(
        enabled: false,
        speedThreshold: 13.41,
        minimumDescentDistance: 200,
        mode: .voiceAndHaptic
    )

    init(
        enabled: Bool = false,
        speedThreshold: Double = 13.41,
        minimumDescentDistance: Double = 200,
        mode: AlertMode = .voiceAndHaptic
    ) {
        self.enabled = enabled
        self.speedThreshold = speedThreshold
        self.minimumDescentDistance = minimumDescentDistance
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        speedThreshold = try c.decodeIfPresent(Double.self, forKey: .speedThreshold) ?? 13.41
        minimumDescentDistance = try c.decodeIfPresent(Double.self, forKey: .minimumDescentDistance) ?? 200
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceAndHaptic
    }
}

// MARK: - Climb Alert Preferences

struct ClimbAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var minimumClimbHeight: Double       // meters (default 30 ≈ 100ft)
    var minimumClimbDistance: Double      // meters
    var climbSeparationDistance: Double   // meters
    var mode: AlertMode

    static let `default` = ClimbAlertPreferences(
        enabled: false,
        minimumClimbHeight: 30,
        minimumClimbDistance: 500,
        climbSeparationDistance: 200,
        mode: .voiceAndHaptic
    )

    init(
        enabled: Bool = false,
        minimumClimbHeight: Double = 30,
        minimumClimbDistance: Double = 500,
        climbSeparationDistance: Double = 200,
        mode: AlertMode = .voiceAndHaptic
    ) {
        self.enabled = enabled
        self.minimumClimbHeight = minimumClimbHeight
        self.minimumClimbDistance = minimumClimbDistance
        self.climbSeparationDistance = climbSeparationDistance
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        minimumClimbHeight = try c.decodeIfPresent(Double.self, forKey: .minimumClimbHeight) ?? 30
        minimumClimbDistance = try c.decodeIfPresent(Double.self, forKey: .minimumClimbDistance) ?? 500
        climbSeparationDistance = try c.decodeIfPresent(Double.self, forKey: .climbSeparationDistance) ?? 200
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceAndHaptic
    }
}

// MARK: - Haptic Preferences

struct HapticPreferences: Codable, Equatable, Hashable {
    var intensity: HapticIntensity

    static let `default` = HapticPreferences(intensity: .medium)

    init(intensity: HapticIntensity = .medium) {
        self.intensity = intensity
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        intensity = try c.decodeIfPresent(HapticIntensity.self, forKey: .intensity) ?? .medium
    }
}

// MARK: - Top-Level Preferences

struct NavigationAlertPreferences: Codable, Equatable, Hashable {
    var turnAlerts: TurnAlertPreferences
    var navigationEvents: NavigationEventPreferences
    var splitAlerts: SplitAlertPreferences
    var autoPauseAlerts: AutoPauseAlertPreferences
    var descentAlerts: DescentAlertPreferences
    var climbAlerts: ClimbAlertPreferences
    var haptics: HapticPreferences

    static let `default` = NavigationAlertPreferences(
        turnAlerts: .default,
        navigationEvents: .default,
        splitAlerts: .default,
        autoPauseAlerts: .default,
        descentAlerts: .default,
        climbAlerts: .default,
        haptics: .default
    )

    init(
        turnAlerts: TurnAlertPreferences = .default,
        navigationEvents: NavigationEventPreferences = .default,
        splitAlerts: SplitAlertPreferences = .default,
        autoPauseAlerts: AutoPauseAlertPreferences = .default,
        descentAlerts: DescentAlertPreferences = .default,
        climbAlerts: ClimbAlertPreferences = .default,
        haptics: HapticPreferences = .default
    ) {
        self.turnAlerts = turnAlerts
        self.navigationEvents = navigationEvents
        self.splitAlerts = splitAlerts
        self.autoPauseAlerts = autoPauseAlerts
        self.descentAlerts = descentAlerts
        self.climbAlerts = climbAlerts
        self.haptics = haptics
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        turnAlerts = try c.decodeIfPresent(TurnAlertPreferences.self, forKey: .turnAlerts) ?? .default
        navigationEvents = try c.decodeIfPresent(NavigationEventPreferences.self, forKey: .navigationEvents) ?? .default
        splitAlerts = try c.decodeIfPresent(SplitAlertPreferences.self, forKey: .splitAlerts) ?? .default
        autoPauseAlerts = try c.decodeIfPresent(AutoPauseAlertPreferences.self, forKey: .autoPauseAlerts) ?? .default
        descentAlerts = try c.decodeIfPresent(DescentAlertPreferences.self, forKey: .descentAlerts) ?? .default
        climbAlerts = try c.decodeIfPresent(ClimbAlertPreferences.self, forKey: .climbAlerts) ?? .default
        haptics = try c.decodeIfPresent(HapticPreferences.self, forKey: .haptics) ?? .default
    }
}
