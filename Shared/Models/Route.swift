//
//  Models.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation

/// A simplified elevation sample preserving major peaks/valleys.
/// Generated on the phone before sending a route to the watch so the watch
/// can render an elevation chart cheaply without iterating thousands of points.
struct ElevationSample: Codable, Equatable, Hashable {
    let distanceFromStart: Double // meters
    let elevation: Double         // meters
}

struct Route: Codable, Identifiable, Equatable, Hashable {
    let id: UUID
    var name: String
    let points: [TrackPoint]
    let waypoints: [Waypoint]?
    let createdAt: Date
    let source: RouteSource?
    /// Simplified elevation profile (typically a few hundred points or fewer).
    /// nil for older routes; computed by `RouteElevationSimplifier` before send-to-watch.
    var simplifiedElevation: [ElevationSample]?
    /// Cue Editor overlay: user-curated decisions on which turns to include,
    /// skip, or rename. Applied at ride time. nil/empty = no curation.
    var cueEdits: CueEdits?

    init(id: UUID = UUID(), name: String, points: [TrackPoint], waypoints: [Waypoint]? = nil, createdAt: Date = Date(), source: RouteSource? = nil, simplifiedElevation: [ElevationSample]? = nil, cueEdits: CueEdits? = nil) {
        self.id = id
        self.name = name
        self.points = points
        self.waypoints = waypoints
        self.createdAt = createdAt
        self.source = source
        self.simplifiedElevation = simplifiedElevation
        self.cueEdits = cueEdits
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        points = try container.decode([TrackPoint].self, forKey: .points)
        waypoints = try container.decodeIfPresent([Waypoint].self, forKey: .waypoints)
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        source = try container.decodeIfPresent(RouteSource.self, forKey: .source)
        simplifiedElevation = try container.decodeIfPresent([ElevationSample].self, forKey: .simplifiedElevation)
        cueEdits = try container.decodeIfPresent(CueEdits.self, forKey: .cueEdits)
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }
    
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
        let minDelta: Double = 4.0
        var refElevation = points.first?.elevation

        for point in points {
            guard let elev = point.elevation, let ref = refElevation else { continue }
            let delta = elev - ref
            if delta > minDelta {
                gain += delta
                refElevation = elev
            } else if delta < -minDelta {
                refElevation = elev
            }
        }
        return gain
    }

    /// Best-available elevation series for chart rendering on resource-constrained
    /// surfaces (the watch). Prefers the precomputed simplified series; falls back
    /// to recomputing on-the-fly from the full track if it's missing.
    var watchElevationSeries: [ElevationSample]? {
        if let s = simplifiedElevation, !s.isEmpty { return s }
        return RouteElevationSimplifier.simplify(self)
    }

    var elevationLoss: Double {
        guard points.count > 1 else { return 0 }
        var loss: Double = 0
        let minDelta: Double = 4.0
        var refElevation = points.first?.elevation

        for point in points {
            guard let elev = point.elevation, let ref = refElevation else { continue }
            let delta = elev - ref
            if delta > minDelta {
                refElevation = elev
            } else if delta < -minDelta {
                loss -= delta
                refElevation = elev
            }
        }
        return loss
    }
}
