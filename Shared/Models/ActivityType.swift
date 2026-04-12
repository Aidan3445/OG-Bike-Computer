//
//  ActivityType.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

enum ActivityType: String, CaseIterable, Codable, Identifiable {
    case cycling
    case running
    case walking
    case hiking

    var id: String { rawValue }

    var name: String {
        switch self {
        case .cycling: return "Cycling"
        case .running: return "Running"
        case .walking: return "Walking"
        case .hiking: return "Hiking"
        }
    }

    var icon: String {
        switch self {
        case .cycling: return "bicycle"
        case .running: return "figure.run"
        case .walking: return "figure.walk"
        case .hiking: return "figure.hiking"
        }
    }

    #if canImport(HealthKit)
    var hkType: HKWorkoutActivityType {
        switch self {
        case .cycling: return .cycling
        case .running: return .running
        case .walking: return .walking
        case .hiking: return .hiking
        }
    }

    var distanceType: HKQuantityType {
        switch self {
        case .cycling: return HKQuantityType(.distanceCycling)
        case .running, .walking, .hiking: return HKQuantityType(.distanceWalkingRunning)
        }
    }
    #endif

    var speedLabel: String {
        switch self {
        case .cycling: return "SPEED"
        case .running, .walking, .hiking: return "PACE"
        }
    }

    var usesPace: Bool {
        switch self {
        case .cycling: return false
        case .running, .walking, .hiking: return true
        }
    }
}

