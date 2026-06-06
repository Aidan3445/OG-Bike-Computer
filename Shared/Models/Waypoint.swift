//
//  Waypoint.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import Foundation
import CoreLocation

/// What a waypoint represents — used to keep turn cues separate from POIs.
enum WaypointKind: String, Codable {
    case turnCue   // a turn instruction the route takes (left, right, etc.)
    case poi       // a point of interest (landmark, water, food, etc.) — not a turn
}

struct Waypoint: Codable, Equatable {
    let id: UUID
    let lat: Double
    let lon: Double
    let name: String         // Direction keyword for turnCue ("Left"); display name for POI ("Mt Washington")
    let description: String? // Full instruction or POI description
    let kind: WaypointKind

    init(id: UUID = UUID(), lat: Double, lon: Double, name: String, description: String? = nil, kind: WaypointKind = .turnCue) {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.name = name
        self.description = description
        self.kind = kind
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // Older route data didn't include an id — synthesize one on decode.
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        lat = try c.decode(Double.self, forKey: .lat)
        lon = try c.decode(Double.self, forKey: .lon)
        name = try c.decode(String.self, forKey: .name)
        description = try c.decodeIfPresent(String.self, forKey: .description)
        // Older route data didn't tag waypoints — they were always turn cues.
        kind = try c.decodeIfPresent(WaypointKind.self, forKey: .kind) ?? .turnCue
    }

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lon)
    }
}

extension Array where Element == Waypoint {
    var turnCues: [Waypoint] { filter { $0.kind == .turnCue } }
    var pois: [Waypoint] { filter { $0.kind == .poi } }
}
