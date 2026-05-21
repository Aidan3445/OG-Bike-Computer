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
    var minimumAlertGap: Double          // seconds between alerts for same turn (default 10)

    static let `default` = TurnAlertPreferences(
        defaultMode: .voiceAndHaptic,
        primaryApproachDistance: 121.92,  // 400ft
        secondaryApproachEnabled: false,
        secondaryApproachDistance: 804.672, // 0.5mi
        atTurnMode: nil,
        primaryApproachMode: nil,
        secondaryApproachMode: nil,
        minimumAlertGap: 10
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
        secondaryApproachMode: AlertMode? = nil,
        minimumAlertGap: Double = 10
    ) {
        self.defaultMode = defaultMode
        self.primaryApproachDistance = primaryApproachDistance
        self.secondaryApproachEnabled = secondaryApproachEnabled
        self.secondaryApproachDistance = secondaryApproachDistance
        self.atTurnMode = atTurnMode
        self.primaryApproachMode = primaryApproachMode
        self.secondaryApproachMode = secondaryApproachMode
        self.minimumAlertGap = minimumAlertGap
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
        minimumAlertGap = try c.decodeIfPresent(Double.self, forKey: .minimumAlertGap) ?? 10
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

// MARK: - Split Stats (passed from WorkoutManager to VoiceNavigator)

/// Cumulative stats over a window — either a single split, the first half of
/// the ride (for halfway alerts), or the full ride to date (for ride-scope
/// stat readouts). Fields default to 0 when there's no data; consumers should
/// use the unit-appropriate "missing" check (e.g. `> 0`) before reading.
struct SplitStats {
    let movingTime: TimeInterval
    let elapsedTime: TimeInterval   // wall-clock seconds, includes paused time
    let distance: Double             // meters
    let averageSpeed: Double         // m/s
    let maxSpeed: Double             // m/s
    let averageHeartRate: Double     // bpm, 0 if no data
    let maxHeartRate: Double         // bpm, 0 if no data
    let elevationGain: Double        // meters
    let elevationLoss: Double        // meters
    let calories: Double             // kcal

    /// Convenience zero/empty stats — used when no data has been collected
    /// yet (e.g. very first split or halfway hit instantly at start).
    static let zero = SplitStats(
        movingTime: 0,
        elapsedTime: 0,
        distance: 0,
        averageSpeed: 0,
        maxSpeed: 0,
        averageHeartRate: 0,
        maxHeartRate: 0,
        elevationGain: 0,
        elevationLoss: 0,
        calories: 0
    )
}

// MARK: - Split Alert Preferences

enum StatScope: String, Codable, CaseIterable, Hashable {
    case split   // just this split/lap
    case ride    // whole ride total
    case both    // read split value then ride value

    var label: String {
        switch self {
        case .split: return "Split"
        case .ride:  return "Ride"
        case .both:  return "Both"
        }
    }
}

struct SplitMetricConfig: Codable, Equatable, Hashable {
    var metric: MetricType
    var scope: StatScope
}

/// Metrics that the watch can actually read aloud as part of a split or
/// halfway readout. Kept in sync with `VoiceNavigator.statText` and the
/// picker UI — anything outside this set silently drops at read time.
let voiceReadableMetrics: Set<MetricType> = [
    .movingTime,
    .elapsedTime,
    .averageSpeed,
    .maxSpeed,
    .distance,
    .averageHeartRate,
    .maxHeartRate,
    .heartRate,            // legacy alias for averageHeartRate
    .elevationGain,
    .elevationLoss,
    .calories
]

struct SplitAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var splitDistance: Double // meters
    var metrics: [SplitMetricConfig]
    var mode: AlertMode

    static let `default` = SplitAlertPreferences(
        enabled: false,
        splitDistance: 1609.34, // 1 mile
        metrics: [
            SplitMetricConfig(metric: .movingTime, scope: .split),
            SplitMetricConfig(metric: .averageSpeed, scope: .split),
            SplitMetricConfig(metric: .distance, scope: .ride)
        ],
        mode: .voiceOnly
    )

    init(
        enabled: Bool = false,
        splitDistance: Double = 1609.34,
        metrics: [SplitMetricConfig]? = nil,
        mode: AlertMode = .voiceOnly
    ) {
        self.enabled = enabled
        self.splitDistance = splitDistance
        self.metrics = metrics ?? Self.default.metrics
        self.mode = mode
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        splitDistance = try c.decodeIfPresent(Double.self, forKey: .splitDistance) ?? 1609.34
        // Backward compat: migrate old selectedMetrics to new metrics format
        let rawMetrics: [SplitMetricConfig]
        if let newMetrics = try c.decodeIfPresent([SplitMetricConfig].self, forKey: .metrics) {
            rawMetrics = newMetrics
        } else if let oldMetrics = try? c.decodeIfPresent([MetricType].self, forKey: .metrics) {
            rawMetrics = oldMetrics.map { SplitMetricConfig(metric: $0, scope: .split) }
        } else {
            rawMetrics = Self.default.metrics
        }
        // Strip metrics the watch can't actually announce (legacy .grade /
        // .powerEstimate selections from older builds) so the rider doesn't
        // think those will be read aloud.
        metrics = rawMetrics.filter { voiceReadableMetrics.contains($0.metric) }
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

// MARK: - Audio Source

/// Where to play voice alerts. `.auto` follows the rule: BT/headphones on the
/// watch first, then the phone if mirrored, then the watch speaker. The
/// explicit modes pin the output regardless of what's connected (with a
/// graceful fallback if the chosen device isn't available).
enum AlertAudioSource: String, Codable, CaseIterable, Hashable {
    case auto
    case watch
    case phone

    var label: String {
        switch self {
        case .auto:  return "Auto"
        case .watch: return "Watch"
        case .phone: return "Phone"
        }
    }

    var detail: String {
        switch self {
        case .auto:  return "Headphones, then phone, then watch speaker"
        case .watch: return "Always play on the watch (or paired headphones)"
        case .phone: return "Always play on the phone if connected"
        }
    }
}

struct AudioOutputPreferences: Codable, Equatable, Hashable {
    var source: AlertAudioSource

    static let `default` = AudioOutputPreferences(source: .auto)

    init(source: AlertAudioSource = .auto) {
        self.source = source
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        source = try c.decodeIfPresent(AlertAudioSource.self, forKey: .source) ?? .auto
    }
}

// MARK: - End-of-Route Alert Preferences

/// Reads back ride stats once the route is completed. Defaults to mirroring
/// the halfway-alert metric list; `useSplitsMetrics = false` lets the rider
/// override with a custom selection (`metricsOverride`).
struct EndOfRouteAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var mode: AlertMode
    /// When true, use the same metrics the rider picked for split/halfway.
    var useSplitsMetrics: Bool
    /// Used only when `useSplitsMetrics` is false. Nil falls back to splits metrics.
    var metricsOverride: [SplitMetricConfig]?

    static let `default` = EndOfRouteAlertPreferences(
        enabled: true,
        mode: .voiceOnly,
        useSplitsMetrics: true,
        metricsOverride: nil
    )

    init(
        enabled: Bool = true,
        mode: AlertMode = .voiceOnly,
        useSplitsMetrics: Bool = true,
        metricsOverride: [SplitMetricConfig]? = nil
    ) {
        self.enabled = enabled
        self.mode = mode
        self.useSplitsMetrics = useSplitsMetrics
        self.metricsOverride = metricsOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceOnly
        useSplitsMetrics = try c.decodeIfPresent(Bool.self, forKey: .useSplitsMetrics) ?? true
        let raw = try c.decodeIfPresent([SplitMetricConfig].self, forKey: .metricsOverride)
        metricsOverride = raw?.filter { voiceReadableMetrics.contains($0.metric) }
    }
}

// MARK: - Waypoint / POI Alert Preferences

/// Announce when approaching POI/waypoints along (or near) the route.
/// Defaults to using the same approach distances as turn alerts;
/// `useCustomDistances` lets the user override them for waypoints alone.
struct WaypointAlertPreferences: Codable, Equatable, Hashable {
    var enabled: Bool
    var mode: AlertMode
    /// When true, use the custom distances below; when false, mirror turn alert distances.
    var useCustomDistances: Bool
    var primaryApproachDistance: Double      // meters
    var secondaryApproachEnabled: Bool
    var secondaryApproachDistance: Double    // meters
    /// Maximum off-route distance (meters) before suppressing a POI alert.
    /// Beyond this the POI is considered too far away to be relevant.
    var maxOffRouteDistance: Double

    static let `default` = WaypointAlertPreferences(
        enabled: true,
        mode: .voiceOnly,
        useCustomDistances: false,
        primaryApproachDistance: 152.4,         // 500ft
        secondaryApproachEnabled: false,
        secondaryApproachDistance: 804.672,     // 0.5mi
        maxOffRouteDistance: 4828.03            // 3 miles
    )

    init(
        enabled: Bool = true,
        mode: AlertMode = .voiceOnly,
        useCustomDistances: Bool = false,
        primaryApproachDistance: Double = 152.4,
        secondaryApproachEnabled: Bool = false,
        secondaryApproachDistance: Double = 804.672,
        maxOffRouteDistance: Double = 4828.03
    ) {
        self.enabled = enabled
        self.mode = mode
        self.useCustomDistances = useCustomDistances
        self.primaryApproachDistance = primaryApproachDistance
        self.secondaryApproachEnabled = secondaryApproachEnabled
        self.secondaryApproachDistance = secondaryApproachDistance
        self.maxOffRouteDistance = maxOffRouteDistance
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
        mode = try c.decodeIfPresent(AlertMode.self, forKey: .mode) ?? .voiceOnly
        useCustomDistances = try c.decodeIfPresent(Bool.self, forKey: .useCustomDistances) ?? false
        primaryApproachDistance = try c.decodeIfPresent(Double.self, forKey: .primaryApproachDistance) ?? 152.4
        secondaryApproachEnabled = try c.decodeIfPresent(Bool.self, forKey: .secondaryApproachEnabled) ?? false
        secondaryApproachDistance = try c.decodeIfPresent(Double.self, forKey: .secondaryApproachDistance) ?? 804.672
        maxOffRouteDistance = try c.decodeIfPresent(Double.self, forKey: .maxOffRouteDistance) ?? 4828.03
    }
}

// MARK: - Top-Level Preferences

struct NavigationAlertPreferences: Codable, Equatable, Hashable {
    var turnAlerts: TurnAlertPreferences
    var navigationEvents: NavigationEventPreferences
    var splitAlerts: SplitAlertPreferences
    var autoPauseAlerts: AutoPauseAlertPreferences
    var waypointAlerts: WaypointAlertPreferences
    var endOfRouteAlerts: EndOfRouteAlertPreferences
    var haptics: HapticPreferences
    var audioOutput: AudioOutputPreferences

    static let `default` = NavigationAlertPreferences(
        turnAlerts: .default,
        navigationEvents: .default,
        splitAlerts: .default,
        autoPauseAlerts: .default,
        waypointAlerts: .default,
        endOfRouteAlerts: .default,
        haptics: .default,
        audioOutput: .default
    )

    init(
        turnAlerts: TurnAlertPreferences = .default,
        navigationEvents: NavigationEventPreferences = .default,
        splitAlerts: SplitAlertPreferences = .default,
        autoPauseAlerts: AutoPauseAlertPreferences = .default,
        waypointAlerts: WaypointAlertPreferences = .default,
        endOfRouteAlerts: EndOfRouteAlertPreferences = .default,
        haptics: HapticPreferences = .default,
        audioOutput: AudioOutputPreferences = .default
    ) {
        self.turnAlerts = turnAlerts
        self.navigationEvents = navigationEvents
        self.splitAlerts = splitAlerts
        self.autoPauseAlerts = autoPauseAlerts
        self.waypointAlerts = waypointAlerts
        self.endOfRouteAlerts = endOfRouteAlerts
        self.haptics = haptics
        self.audioOutput = audioOutput
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        turnAlerts = try c.decodeIfPresent(TurnAlertPreferences.self, forKey: .turnAlerts) ?? .default
        navigationEvents = try c.decodeIfPresent(NavigationEventPreferences.self, forKey: .navigationEvents) ?? .default
        splitAlerts = try c.decodeIfPresent(SplitAlertPreferences.self, forKey: .splitAlerts) ?? .default
        autoPauseAlerts = try c.decodeIfPresent(AutoPauseAlertPreferences.self, forKey: .autoPauseAlerts) ?? .default
        waypointAlerts = try c.decodeIfPresent(WaypointAlertPreferences.self, forKey: .waypointAlerts) ?? .default
        endOfRouteAlerts = try c.decodeIfPresent(EndOfRouteAlertPreferences.self, forKey: .endOfRouteAlerts) ?? .default
        haptics = try c.decodeIfPresent(HapticPreferences.self, forKey: .haptics) ?? .default
        audioOutput = try c.decodeIfPresent(AudioOutputPreferences.self, forKey: .audioOutput) ?? .default
    }
}
