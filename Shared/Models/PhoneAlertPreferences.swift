//
//  PhoneAlertPreferences.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import Foundation

// MARK: - Phone Alert Mode

enum PhoneAlertMode: String, Codable, CaseIterable, Hashable {
    case off
    case liveActivity
    case turnNotifications

    var label: String {
        switch self {
        case .off: return "Off"
        case .liveActivity: return "Live Activity"
        case .turnNotifications: return "Notifications"
        }
    }
}

// MARK: - Live Activity Stat Slot

/// A single metric slot in the Live Activity lock-screen stats grid.
/// Uses MetricType raw values for Codable compatibility without importing MetricType here.
struct LiveActivitySlot: Codable, Equatable, Hashable, Identifiable {
    var id: Int        // 0-5 position index
    var metricType: MetricType

    static let defaultSlots: [LiveActivitySlot] = [
        LiveActivitySlot(id: 0, metricType: .distance),
        LiveActivitySlot(id: 1, metricType: .movingTime),
        LiveActivitySlot(id: 2, metricType: .averageSpeed),
        LiveActivitySlot(id: 3, metricType: .heartRate),
        LiveActivitySlot(id: 4, metricType: .elevationGain),
        LiveActivitySlot(id: 5, metricType: .speed),
    ]
}

// MARK: - Phone Alert Preferences

struct PhoneAlertPreferences: Codable, Equatable, Hashable {
    var mode: PhoneAlertMode
    var liveActivityShowMap: Bool
    var liveActivitySlots: [LiveActivitySlot]

    static let `default` = PhoneAlertPreferences(
        mode: .liveActivity,
        liveActivityShowMap: true,
        liveActivitySlots: LiveActivitySlot.defaultSlots
    )

    init(
        mode: PhoneAlertMode = .liveActivity,
        liveActivityShowMap: Bool = true,
        liveActivitySlots: [LiveActivitySlot] = LiveActivitySlot.defaultSlots
    ) {
        self.mode = mode
        self.liveActivityShowMap = liveActivityShowMap
        self.liveActivitySlots = liveActivitySlots
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(PhoneAlertMode.self, forKey: .mode) ?? .liveActivity
        liveActivityShowMap = try c.decodeIfPresent(Bool.self, forKey: .liveActivityShowMap) ?? true
        liveActivitySlots = try c.decodeIfPresent([LiveActivitySlot].self, forKey: .liveActivitySlots) ?? LiveActivitySlot.defaultSlots
    }
}
