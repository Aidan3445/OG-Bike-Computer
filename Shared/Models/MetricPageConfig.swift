//
//  MetricPageConfig.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import Foundation

struct MetricSlot: Codable, Identifiable, Equatable, Hashable {
    var id: UUID
    var type: MetricType

    init(id: UUID = UUID(), type: MetricType) {
        self.id = id
        self.type = type
    }
}

struct MetricPage: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    /// Metrics displayed on this page, laid out in rows of 2
    var slots: [MetricSlot]

    static let maxSlots = 6

    init(id: UUID = UUID(), name: String, slots: [MetricSlot]) {
        self.id = id
        self.name = name
        self.slots = slots
    }

    init(id: UUID = UUID(), name: String, metrics: [MetricType]) {
        self.id = id
        self.name = name
        self.slots = metrics.map { MetricSlot(type: $0) }
    }
}

struct MetricPagesConfig: Codable, Equatable {
    var pages: [MetricPage]

    static var `default`: MetricPagesConfig {
        MetricPagesConfig(pages: [
            MetricPage(name: "Main", metrics: [
                .speed, .distance,
                .elapsedTime, .movingTime,
                .heartRate, .calories
            ]),
            MetricPage(name: "Performance", metrics: [
                .averageSpeed, .maxSpeed,
                .powerEstimate, .grade,
                .elevationGain, .elevationLoss
            ]),
            MetricPage(name: "Elevation", metrics: [
                .currentElevation, .highestElevation,
                .elevationGain, .elevationLoss,
                .grade, .distance
            ])
        ])
    }
}
