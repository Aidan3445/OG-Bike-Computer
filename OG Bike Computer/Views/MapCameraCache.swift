//
//  MapCameraCache.swift
//  OG Bike Computer
//
//  Process-lifetime cache that remembers each detail-view map's last camera
//  (center + distance + heading + pitch). Lets the user open a route detail,
//  pan/zoom/rotate, dismiss the screen, and come back to find the map
//  exactly where they left it — even when SwiftUI tears down the view
//  hierarchy in between (e.g. the route-detail sheet from RideControlView is
//  recreated every time it's presented, so internal @State is lost).
//
//  Keyed by a string so callers can mix UUIDs (Route.id / RideSummary.id),
//  hashes (Multi-ride selection), or anything else that uniquely identifies
//  the map view. Storage is in-memory only — restarting the app starts
//  fresh, which matches the user's mental model of "this is just where I
//  had the map last".
//

import Foundation
import MapKit
import SwiftUI  // for MapCamera

@MainActor
final class MapCameraCache {
    static let shared = MapCameraCache()

    private var cameras: [String: MapCamera] = [:]

    private init() {}

    func camera(for key: String) -> MapCamera? {
        cameras[key]
    }

    func store(_ camera: MapCamera, for key: String) {
        cameras[key] = camera
    }

    func clear(_ key: String) {
        cameras.removeValue(forKey: key)
    }
}
