//
//  BatteryManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

class BatteryManager {

    enum GPSMode: String {
        case full
        case balanced
        case power
    }

    private(set) var currentMode: GPSMode = .full

    func recommendedMode(
        distanceToNextTurn: Double,
        isOffRoute: Bool,
        speed: Double,
        floor: GPSAccuracyFloor = .best,
        dynamicOptimization: Bool = true
    ) -> GPSMode {
        // When dynamic optimization is off, always use the floor setting
        guard dynamicOptimization else {
            switch floor {
            case .best: return .full
            case .balanced: return .balanced
            case .powerSaver: return .power
            }
        }

        let dynamic: GPSMode
        if isOffRoute {
            dynamic = .full
        } else if distanceToNextTurn < 300 {
            dynamic = .full
        } else if speed > 5 { // > ~11 mph
            dynamic = .balanced
        } else {
            dynamic = .power
        }

        return applyFloor(dynamic, floor: floor)
    }

    private func applyFloor(_ mode: GPSMode, floor: GPSAccuracyFloor) -> GPSMode {
        switch floor {
        case .best: return .full
        case .balanced: return mode == .power ? .balanced : mode
        case .powerSaver: return mode
        }
    }

    func apply(mode: GPSMode, to manager: CLLocationManager) {
        guard mode != currentMode else { return }
        currentMode = mode

        switch mode {
        case .full:
            manager.desiredAccuracy = kCLLocationAccuracyBest
            manager.distanceFilter = kCLDistanceFilterNone
        case .balanced:
            manager.desiredAccuracy = kCLLocationAccuracyNearestTenMeters
            manager.distanceFilter = 5
        case .power:
            manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
            manager.distanceFilter = 10
        }
    }
}
