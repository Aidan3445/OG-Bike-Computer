//
//  TrackPoint.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import CoreLocation

struct TrackPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let elevation: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

