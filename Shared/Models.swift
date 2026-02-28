//
//  Models.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

struct TrackPoint: Codable, Equatable {
    let lat: Double
    let lon: Double
    let elevation: Double?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

struct Route: Codable, Identifiable, Equatable {
    let id: UUID
    let name: String
    let points: [TrackPoint]

    var distance: Double {
        guard points.count > 1 else { return 0 }
        var total: Double = 0
        for i in 1..<points.count {
            let prev = CLLocation(latitude: points[i-1].lat, longitude: points[i-1].lon)
            let curr = CLLocation(latitude: points[i].lat, longitude: points[i].lon)
            total += curr.distance(from: prev)
        }
        return total
    }

    var elevationGain: Double {
        guard points.count > 1 else { return 0 }
        var gain: Double = 0
        for i in 1..<points.count {
            if let curr = points[i].elevation, let prev = points[i-1].elevation {
                let delta = curr - prev
                if delta > 0 { gain += delta }
            }
        }
        return gain
    }

    var elevationLoss: Double {
        guard points.count > 1 else { return 0 }
        var loss: Double = 0
        for i in 1..<points.count {
            if let curr = points[i].elevation, let prev = points[i-1].elevation {
                let delta = curr - prev
                if delta < 0 { loss -= delta }
            }
        }
        return loss
    }
}
