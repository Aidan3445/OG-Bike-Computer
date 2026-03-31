//
//  SettingsPreset.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/30/26.
//

import Foundation

struct SettingsPreset: Codable, Identifiable, Equatable {
    let id: UUID
    var name: String
    var settings: UserSettings
    var metricConfig: MetricPagesConfig

    init(name: String, settings: UserSettings, metricConfig: MetricPagesConfig = .default) {
        self.id = UUID()
        self.name = name
        self.settings = settings
        self.metricConfig = metricConfig
    }

    private enum CodingKeys: String, CodingKey {
        case id, name, settings, metricConfig
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(UUID.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        settings = try c.decode(UserSettings.self, forKey: .settings)
        metricConfig = try c.decodeIfPresent(MetricPagesConfig.self, forKey: .metricConfig) ?? .default
    }
}
