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

// MARK: - Phone Alert Preferences

struct PhoneAlertPreferences: Codable, Equatable, Hashable {
    var mode: PhoneAlertMode
    var liveActivityShowMap: Bool

    static let `default` = PhoneAlertPreferences(
        mode: .liveActivity,
        liveActivityShowMap: true
    )

    init(mode: PhoneAlertMode = .liveActivity, liveActivityShowMap: Bool = true) {
        self.mode = mode
        self.liveActivityShowMap = liveActivityShowMap
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        mode = try c.decodeIfPresent(PhoneAlertMode.self, forKey: .mode) ?? .liveActivity
        liveActivityShowMap = try c.decodeIfPresent(Bool.self, forKey: .liveActivityShowMap) ?? true
    }
}
