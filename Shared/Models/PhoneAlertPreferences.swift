//
//  PhoneAlertPreferences.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import Foundation

// MARK: - Live Activity Stat Slot

/// A single metric slot in the Live Activity lock-screen stats grid.
/// Uses MetricType raw values for Codable compatibility without importing MetricType here.
struct LiveActivitySlot: Codable, Equatable, Hashable, Identifiable {
    var id: Int        // 0-5 position index
    var metricType: MetricType

    static let defaultSlots: [LiveActivitySlot] = [
        LiveActivitySlot(id: 0, metricType: .distance),
        LiveActivitySlot(id: 1, metricType: .movingTime),
        LiveActivitySlot(id: 2, metricType: .speed),
        LiveActivitySlot(id: 3, metricType: .heartRate),
        LiveActivitySlot(id: 4, metricType: .elevationGain),
        LiveActivitySlot(id: 5, metricType: .averageSpeed),
    ]

    /// Automatic no-route fallback for a Remaining slot: the first eligible
    /// stat that doesn't itself require a route and isn't already in the grid.
    static func automaticRemainingFallback(for slots: [LiveActivitySlot]) -> MetricType {
        let used = Set(slots.map(\.metricType))
        return MetricType.liveActivityStats.first {
            !$0.requiresRoute && !used.contains($0)
        } ?? .distance
    }
}

// MARK: - Phone Alert Preferences
//
// The Live Activity is always present during a mirrored workout (it satisfies
// the HK mirroring 10-second grace window and is what keeps the iPhone app
// alive for reliable voice alert delivery). The only user-facing choice here
// is whether to ALSO post banner Turn Notifications when navigation events
// fire, and how to customize the Live Activity contents.

struct PhoneAlertPreferences: Codable, Equatable, Hashable {
    /// When true, the phone posts a banner notification on every navigation
    /// turn alert in addition to playing the spoken alert. The Live Activity
    /// is always shown regardless of this setting.
    var showTurnNotifications: Bool
    /// Which metric slots appear in the Live Activity stats grid.
    var liveActivitySlots: [LiveActivitySlot]
    /// Stat shown in place of a Remaining slot on rides without a route.
    /// nil = automatic (first eligible stat not already in the grid).
    var distanceRemainingFallback: MetricType?
    /// When true, the top row of `liveActivitySlots` also renders in the
    /// expanded Dynamic Island on devices that have one.
    var showStatsInDynamicIsland: Bool

    /// The fallback that will actually be used, resolving automatic mode.
    var resolvedRemainingFallback: MetricType {
        distanceRemainingFallback ?? LiveActivitySlot.automaticRemainingFallback(for: liveActivitySlots)
    }

    static let `default` = PhoneAlertPreferences(
        showTurnNotifications: false,
        liveActivitySlots: LiveActivitySlot.defaultSlots
    )

    init(
        showTurnNotifications: Bool = false,
        liveActivitySlots: [LiveActivitySlot] = LiveActivitySlot.defaultSlots,
        distanceRemainingFallback: MetricType? = nil,
        showStatsInDynamicIsland: Bool = true
    ) {
        self.showTurnNotifications = showTurnNotifications
        self.liveActivitySlots = liveActivitySlots
        self.distanceRemainingFallback = distanceRemainingFallback
        self.showStatsInDynamicIsland = showStatsInDynamicIsland
    }

    // Old wire format: `mode: PhoneAlertMode` (off / liveActivity /
    // turnNotifications). Migration preserves the only meaningful
    // distinction — were notifications on?
    private enum LegacyMode: String, Codable {
        case off, liveActivity, turnNotifications
    }
    private enum CodingKeys: String, CodingKey {
        case showTurnNotifications
        case mode  // legacy
        case liveActivitySlots
        case distanceRemainingFallback
        case showStatsInDynamicIsland
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        if let new = try c.decodeIfPresent(Bool.self, forKey: .showTurnNotifications) {
            showTurnNotifications = new
        } else if let legacy = try c.decodeIfPresent(LegacyMode.self, forKey: .mode) {
            showTurnNotifications = (legacy == .turnNotifications)
        } else {
            showTurnNotifications = false
        }
        liveActivitySlots = try c.decodeIfPresent([LiveActivitySlot].self, forKey: .liveActivitySlots) ?? LiveActivitySlot.defaultSlots
        distanceRemainingFallback = try c.decodeIfPresent(MetricType.self, forKey: .distanceRemainingFallback)
        showStatsInDynamicIsland = try c.decodeIfPresent(Bool.self, forKey: .showStatsInDynamicIsland) ?? true
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(showTurnNotifications, forKey: .showTurnNotifications)
        try c.encode(liveActivitySlots, forKey: .liveActivitySlots)
        try c.encodeIfPresent(distanceRemainingFallback, forKey: .distanceRemainingFallback)
        try c.encode(showStatsInDynamicIsland, forKey: .showStatsInDynamicIsland)
    }
}
