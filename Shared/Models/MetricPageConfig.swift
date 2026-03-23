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
            MetricPage(name: "Ride", metrics: [
                .distance, .movingTime,
                .speed, .averageSpeed,
                .heartRate, .currentElevation
            ]),
            MetricPage(name: "Climb", metrics: [
                .elevationGain, .elevationLoss,
                .grade, .powerEstimate,
                .elapsedTime, .calories
            ])
        ])
    }
}
