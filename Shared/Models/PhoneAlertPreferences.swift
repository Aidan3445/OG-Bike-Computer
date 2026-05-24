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
    /// Whether the Live Activity includes the map preview tile.
    var liveActivityShowMap: Bool
    /// Which metric slots appear in the Live Activity stats grid.
    var liveActivitySlots: [LiveActivitySlot]

    static let `default` = PhoneAlertPreferences(
        showTurnNotifications: false,
        liveActivityShowMap: true,
        liveActivitySlots: LiveActivitySlot.defaultSlots
    )

    init(
        showTurnNotifications: Bool = false,
        liveActivityShowMap: Bool = true,
        liveActivitySlots: [LiveActivitySlot] = LiveActivitySlot.defaultSlots
    ) {
        self.showTurnNotifications = showTurnNotifications
        self.liveActivityShowMap = liveActivityShowMap
        self.liveActivitySlots = liveActivitySlots
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
        case liveActivityShowMap
        case liveActivitySlots
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
        liveActivityShowMap = try c.decodeIfPresent(Bool.self, forKey: .liveActivityShowMap) ?? true
        liveActivitySlots = try c.decodeIfPresent([LiveActivitySlot].self, forKey: .liveActivitySlots) ?? LiveActivitySlot.defaultSlots
    }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(showTurnNotifications, forKey: .showTurnNotifications)
        try c.encode(liveActivityShowMap, forKey: .liveActivityShowMap)
        try c.encode(liveActivitySlots, forKey: .liveActivitySlots)
    }
}
