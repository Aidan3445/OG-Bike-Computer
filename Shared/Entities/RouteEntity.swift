//
//  RouteEntity.swift
//  OG Bike Computer
//
//  App Entity wrapper for Route, enabling Shortcuts/Siri integration.
//

import AppIntents
import Foundation

struct RouteEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Route")

    static var defaultQuery = RouteEntityQuery()

    /// Sentinel ID representing "no route / free ride".
    static let freeRideID = UUID(uuidString: "00000000-0000-0000-0000-000000000000")!
    static let freeRide   = RouteEntity(id: freeRideID, name: "Free Ride", distance: -1)

    var id: UUID
    var name: String
    var distance: Double // meters

    var isFreeRide: Bool { id == RouteEntity.freeRideID }

    var displayRepresentation: DisplayRepresentation {
        if isFreeRide {
            return DisplayRepresentation(title: "Free Ride", subtitle: "No route")
        }
        let distStr = distance > 0
            ? String(format: " (%.1f mi)", distance / 1609.34)
            : ""
        return DisplayRepresentation(title: "\(name)", subtitle: "\(distStr)")
    }
}

struct RouteEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RouteEntity] {
        let all = [RouteEntity.freeRide] + (await loadRouteEntities())
        return all.filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RouteEntity] {
        let routes = await loadRouteEntities()
        // No saved routes — return empty so optional route params are skipped entirely.
        guard !routes.isEmpty else { return [] }
        return [RouteEntity.freeRide] + routes
    }

    func defaultResult() async -> RouteEntity? {
        nil
    }
}

extension RouteEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [RouteEntity] {
        let routes = await loadRouteEntities()
        guard !routes.isEmpty else { return [] }
        let all = [RouteEntity.freeRide] + routes
        guard !string.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

/// Loads route metadata directly from disk (Documents/routes/*.json).
/// Decodes the full Route model since distance is a computed property.
private func loadRouteEntities() -> [RouteEntity] {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let dir = docs.appendingPathComponent("routes", isDirectory: true)
    guard let files = try? FileManager.default.contentsOfDirectory(
        at: dir, includingPropertiesForKeys: nil
    ) else { return [] }

    return files.compactMap { url -> RouteEntity? in
        guard url.pathExtension == "json",
              let data = try? Data(contentsOf: url),
              let route = try? JSONDecoder().decode(Route.self, from: data)
        else { return nil }

        return RouteEntity(id: route.id, name: route.name, distance: route.distance)
    }
}
