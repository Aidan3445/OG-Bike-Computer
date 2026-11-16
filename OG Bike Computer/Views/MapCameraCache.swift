//
//  MapCameraCache.swift
//  OG Bike Computer
//
//  Remembers each detail map's last camera for the life of the app, so
//  reopening a route or ride puts the map back where the rider left it.
//  Views like the route sheet from RideControlView are rebuilt on every
//  present, so @State alone can't hold it.
//
//  Keyed by any string that identifies the map (route or ride UUID, a hash
//  of a multi-ride selection).
//

import Foundation
import MapKit
import SwiftUI  // for MapCamera

@MainActor
final class MapCameraCache {
    static let shared = MapCameraCache()

    /// Closest zoom the detail maps allow. Street-level zoom can freeze the
    /// map when tiles can't load offline.
    static let minimumDistance: CLLocationDistance = 150

    private var cameras: [String: MapCamera] = [:]

    private init() {}

    func camera(for key: String) -> MapCamera? {
        cameras[key]
    }

    func store(_ camera: MapCamera, for key: String) {
        guard camera.distance < Self.minimumDistance else {
            cameras[key] = camera
            return
        }
        cameras[key] = MapCamera(
            centerCoordinate: camera.centerCoordinate,
            distance: Self.minimumDistance,
            heading: camera.heading,
            pitch: camera.pitch
        )
    }

    func clear(_ key: String) {
        cameras.removeValue(forKey: key)
    }
}
