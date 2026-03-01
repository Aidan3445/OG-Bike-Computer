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
        speed: Double
    ) -> GPSMode {
        if isOffRoute { return .full }

        if distanceToNextTurn < 300 { return .full }

        if speed > 5 { return .balanced } // > ~11 mph

        return .power
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
