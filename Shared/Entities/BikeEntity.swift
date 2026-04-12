//
//  BikeEntity.swift
//  OG Bike Computer
//
//  App Entity wrapper for BikePreset, enabling Shortcuts/Siri bike selection.
//

import AppIntents
import Foundation

struct BikeEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Bike")

    static var defaultQuery = BikeEntityQuery()

    var id: UUID
    var name: String
    var weight: Double // kg

    var displayRepresentation: DisplayRepresentation {
        let weightStr = String(format: "%.1f kg", weight)
        return DisplayRepresentation(
            title: "\(name)",
            subtitle: "\(weightStr)"
        )
    }
}

struct BikeEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [BikeEntity] {
        await loadBikeEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [BikeEntity] {
        await loadBikeEntities()
    }

    func defaultResult() async -> BikeEntity? {
        let bikes = await loadBikeEntities()
        let settings = await loadUserSettings()
        return bikes.first { $0.id == settings?.activeBikeID } ?? bikes.first
    }
}

extension BikeEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [BikeEntity] {
        let all = await loadBikeEntities()
        guard !string.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

private func loadBikeEntities() -> [BikeEntity] {
    guard let settings = loadUserSettings() else { return [] }
    return settings.bikes.map { BikeEntity(id: $0.id, name: $0.name, weight: $0.weight) }
}

private func loadUserSettings() -> UserSettings? {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent("userSettings.json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(UserSettings.self, from: data)
}
