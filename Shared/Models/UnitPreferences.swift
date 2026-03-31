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

struct UnitPreferences: Codable, Equatable, Hashable {
    var speed: SpeedUnit
    var distance: DistanceUnit
    var elevation: ElevationUnit

    static let imperial = UnitPreferences(speed: .mph, distance: .miles, elevation: .feet)
    static let metric = UnitPreferences(speed: .kmh, distance: .kilometers, elevation: .meters)
    static let `default` = imperial

    /// Returns the blanket system if all dimensions match, nil if mixed
    var system: MeasurementSystem? {
        if self == .imperial { return .imperial }
        if self == .metric { return .metric }
        return nil
    }

    /// Overwrite all dimensions to match a blanket system
    mutating func apply(_ system: MeasurementSystem) {
        switch system {
        case .imperial: self = .imperial
        case .metric: self = .metric
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
