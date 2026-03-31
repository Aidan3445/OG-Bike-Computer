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

struct TrackPoint5 {
    let lat: Double
    let lon: Double
    let altitude: Double
    let timestamp: TimeInterval
    let heartRate: Double   // 0 = no data
    let power: Double       // 0 = no data
}

struct TrackEncoder {
    // Version markers
    private static let v4PointSize = 32  // 4 × 8 bytes
    private static let v5PointSize = 48  // 6 × 8 bytes
    private static let v5Magic: UInt32 = 0x54524B35  // "TRK5"
    private static let magicSize = 4

    // MARK: - Encode

    /// Encode v4 (legacy, no HR/power)
    static func encode(_ locations: [CLLocation]) -> Data {
        var data = Data(capacity: locations.count * v4PointSize)
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

    /// Encode v5 with per-point HR and power
    static func encodeV5(_ locations: [CLLocation], heartRates: [Double?], powers: [Double?]) -> Data {
        var magic = v5Magic
        var data = Data(capacity: magicSize + locations.count * v5PointSize)
        data.append(Data(bytes: &magic, count: magicSize))

        for (i, loc) in locations.enumerated() {
            var lat = loc.coordinate.latitude
            var lon = loc.coordinate.longitude
            var alt = loc.altitude
            var ts = loc.timestamp.timeIntervalSince1970
            var hr = (i < heartRates.count ? heartRates[i] : nil) ?? 0.0
            var pw = (i < powers.count ? powers[i] : nil) ?? 0.0
            data.append(Data(bytes: &lat, count: 8))
            data.append(Data(bytes: &lon, count: 8))
            data.append(Data(bytes: &alt, count: 8))
            data.append(Data(bytes: &ts, count: 8))
            data.append(Data(bytes: &hr, count: 8))
            data.append(Data(bytes: &pw, count: 8))
        }
        return data
    }

    // MARK: - Decode

    /// Auto-detect format and decode
    static func decode(_ data: Data) -> [TrackPoint4] {
        if isV5(data) {
            return decodeV5(data).map { pt in
                TrackPoint4(lat: pt.lat, lon: pt.lon, altitude: pt.altitude, timestamp: pt.timestamp)
            }
        }
        return decodeV4(data)
    }

    /// Decode with extended data (HR/power). Falls back gracefully for v4.
    static func decodeV5Full(_ data: Data) -> [TrackPoint5] {
        if isV5(data) {
            return decodeV5(data)
        }
        // v4 fallback — no HR/power
        return decodeV4(data).map { pt in
            TrackPoint5(lat: pt.lat, lon: pt.lon, altitude: pt.altitude, timestamp: pt.timestamp, heartRate: 0, power: 0)
        }
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

    // MARK: - Private

    private static func isV5(_ data: Data) -> Bool {
        guard data.count >= magicSize else { return false }
        let magic = data.withUnsafeBytes { $0.load(as: UInt32.self) }
        return magic == v5Magic
    }

    private static func decodeV4(_ data: Data) -> [TrackPoint4] {
        let count = data.count / v4PointSize
        var points: [TrackPoint4] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let offset = i * v4PointSize
            let lat = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
            let lon = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: Double.self) }
            let alt = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 16, as: Double.self) }
            let ts  = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 24, as: Double.self) }
            points.append(TrackPoint4(lat: lat, lon: lon, altitude: alt, timestamp: ts))
        }
        return points
    }

    private static func decodeV5(_ data: Data) -> [TrackPoint5] {
        let payloadData = data.dropFirst(magicSize)
        let count = payloadData.count / v5PointSize
        var points: [TrackPoint5] = []
        points.reserveCapacity(count)

        for i in 0..<count {
            let offset = magicSize + i * v5PointSize
            let lat = data.withUnsafeBytes { $0.load(fromByteOffset: offset, as: Double.self) }
            let lon = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 8, as: Double.self) }
            let alt = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 16, as: Double.self) }
            let ts  = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 24, as: Double.self) }
            let hr  = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 32, as: Double.self) }
            let pw  = data.withUnsafeBytes { $0.load(fromByteOffset: offset + 40, as: Double.self) }
            points.append(TrackPoint5(lat: lat, lon: lon, altitude: alt, timestamp: ts, heartRate: hr, power: pw))
        }
        return points
    }
}
