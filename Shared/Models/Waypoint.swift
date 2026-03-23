//
//  Waypoint.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import Foundation
import CoreLocation

struct Waypoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let name: String         // Direction keyword: "Left", "Right", "Slight Left", etc.
    let description: String? // Full instruction: "Turn right onto West School Street"

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}
