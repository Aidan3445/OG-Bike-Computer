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

    var id: UUID
    var name: String
    var distance: Double // meters

    var displayRepresentation: DisplayRepresentation {
        let distStr = distance > 0
            ? String(format: " (%.1f mi)", distance / 1609.34)
            : ""
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(distStr)"
        )
    }
}

struct RouteEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [RouteEntity] {
        await loadRouteEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [RouteEntity] {
        await loadRouteEntities()
    }

    func defaultResult() async -> RouteEntity? {
        nil
    }
}

extension RouteEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [RouteEntity] {
        let all = await loadRouteEntities()
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
