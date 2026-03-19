//
//  TrackEncoder.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import CoreLocation

struct TrackPoint4 {
    let lat: Double
    let lon: Double
    let altitude: Double
    let timestamp: TimeInterval
}

struct TrackEncoder {
    static func encode(_ locations: [CLLocation]) -> Data {
        var data = Data(capacity: locations.count * 32)
        for loc in locations {
            var lat = loc.coordinate.latitude
            var lon = loc.coordinate.longitude
            var alt = loc.altitude
            var ts = loc.timestamp.timeIntervalSince1970
            data.append(Data(bytes: &lat, count: 8))
            data.append(Data(bytes: &lon, count: 8))
            data.append(Data(bytes: &alt, count: 8))
            data.append(Data(bytes: &ts, count: 8))
        }
        return data
    }

    static func decode(_ data: Data) -> [TrackPoint4] {
        let pointSize = 32
        let count = data.count / pointSize
        var points: [TrackPoint4] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let offset = i * pointSize
            let lat = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
            let lon = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: Double.self) }
            let alt = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 16, as: Double.self) }
            let ts  = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 24, as: Double.self) }
            points.append(TrackPoint4(lat: lat, lon: lon, altitude: alt, timestamp: ts))
        }

        return points
    }

    static func toLocations(_ points: [TrackPoint4]) -> [CLLocation] {
        points.map { pt in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon),
                altitude: pt.altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: Date(timeIntervalSince1970: pt.timestamp))
        }
    }
}
