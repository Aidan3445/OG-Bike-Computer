//
//  UnitPreferences.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/27/26.
//

import Foundation
import Combine

enum MeasurementSystem: String, Codable, CaseIterable {
    case imperial, metric

    var label: String {
        switch self {
        case .imperial: return "Imperial"
        case .metric: return "Metric"
        }
    }
}

enum SpeedUnit: String, Codable, CaseIterable {
    case mph, kmh

    var label: String {
        switch self {
        case .mph: return "mph"
        case .kmh: return "km/h"
        }
    }

    var paceLabel: String {
        switch self {
        case .mph: return "min/mi"
        case .kmh: return "min/km"
        }
    }
}

enum DistanceUnit: String, Codable, CaseIterable {
    case miles, kilometers

    var label: String {
        switch self {
        case .miles: return "mi"
        case .kilometers: return "km"
        }
    }
}

enum ElevationUnit: String, Codable, CaseIterable {
    case feet, meters

    var label: String {
        switch self {
        case .feet: return "ft"
        case .meters: return "m"
        }
    }
}

enum WeightUnit: String, Codable, CaseIterable {
    case pounds, kilograms

    var label: String {
        switch self {
        case .pounds: return "lbs"
        case .kilograms: return "kg"
        }
    }
}

struct UnitPreferences: Codable, Equatable, Hashable {
    var speed: SpeedUnit
    var distance: DistanceUnit
    var elevation: ElevationUnit
    var weight: WeightUnit
    /// When true, the user has explicitly opted into per-dimension overrides.
    /// Independent of whether the dimensions happen to match a clean system.
    var isCustom: Bool

    static let imperial = UnitPreferences(speed: .mph, distance: .miles, elevation: .feet, weight: .pounds, isCustom: false)
    static let metric = UnitPreferences(speed: .kmh, distance: .kilometers, elevation: .meters, weight: .kilograms, isCustom: false)
    static let `default` = imperial

    init(
        speed: SpeedUnit,
        distance: DistanceUnit,
        elevation: ElevationUnit,
        weight: WeightUnit,
        isCustom: Bool = false
    ) {
        self.speed = speed
        self.distance = distance
        self.elevation = elevation
        self.weight = weight
        self.isCustom = isCustom
    }

    /// Returns the blanket system when the user is not in Custom mode and all
    /// dimensions match. Nil when the user has opted into Custom, or when the
    /// dimensions don't match a single system.
    var system: MeasurementSystem? {
        if isCustom { return nil }
        if speed == .mph && distance == .miles && elevation == .feet && weight == .pounds { return .imperial }
        if speed == .kmh && distance == .kilometers && elevation == .meters && weight == .kilograms { return .metric }
        return nil
    }

    /// Overwrite all dimensions to match a blanket system and leave Custom.
    mutating func apply(_ system: MeasurementSystem) {
        switch system {
        case .imperial:
            self = .imperial
        case .metric:
            self = .metric
        }
    }

    /// Enter Custom mode without touching the per-dimension values. Users then
    /// tune each dimension individually via the Custom Units section.
    mutating func enterCustom() {
        isCustom = true
    }

    // Migration-safe decoding:
    //   - pre-isCustom data infers isCustom from whether the dimensions
    //     already form a mixed set (not all imperial, not all metric).
    //   - pre-weight data falls back to the distance choice (mi -> lbs,
    //     km -> kg) so no one's rider weight silently flips units.
    enum CodingKeys: String, CodingKey {
        case speed, distance, elevation, weight, isCustom
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        speed = try c.decodeIfPresent(SpeedUnit.self, forKey: .speed) ?? .mph
        distance = try c.decodeIfPresent(DistanceUnit.self, forKey: .distance) ?? .miles
        elevation = try c.decodeIfPresent(ElevationUnit.self, forKey: .elevation) ?? .feet
        if let storedWeight = try c.decodeIfPresent(WeightUnit.self, forKey: .weight) {
            weight = storedWeight
        } else {
            weight = (distance == .miles) ? .pounds : .kilograms
        }
        if let stored = try c.decodeIfPresent(Bool.self, forKey: .isCustom) {
            isCustom = stored
        } else {
            let allImperial = speed == .mph && distance == .miles && elevation == .feet && weight == .pounds
            let allMetric = speed == .kmh && distance == .kilometers && elevation == .meters && weight == .kilograms
            isCustom = !(allImperial || allMetric)
        }
    }
}

/// Observable wrapper so SwiftUI views re-render when units change.
/// Use `UnitState.shared` as `@ObservedObject` in any view that displays unit-dependent text.
/// Setting `.preferences` automatically updates the `currentUnits` global.
final class UnitState: ObservableObject {
    static let shared = UnitState()
    @Published var preferences: UnitPreferences = .default {
        didSet { currentUnits = preferences }
    }
    private init() {}
}
