//
//  SettingsProfileEntity.swift
//  OG Bike Computer
//
//  App Entity wrapper for SettingsPreset, enabling Shortcuts/Siri profile switching.
//

import AppIntents
import Foundation

struct SettingsProfileEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Settings Profile")

    static var defaultQuery = SettingsProfileEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SettingsProfileEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SettingsProfileEntity] {
        await loadProfileEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SettingsProfileEntity] {
        await loadProfileEntities()
    }

    func defaultResult() async -> SettingsProfileEntity? {
        let profiles = await loadProfileEntities()
        let activeID = UserDefaults.standard.string(forKey: "activePresetID")
            .flatMap { UUID(uuidString: $0) }
        return profiles.first { $0.id == activeID } ?? profiles.first
    }
}

extension SettingsProfileEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SettingsProfileEntity] {
        let all = await loadProfileEntities()
        guard !string.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

private func loadProfileEntities() -> [SettingsProfileEntity] {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent("settingsPresets.json")
    guard let data = try? Data(contentsOf: url),
          let presets = try? JSONDecoder().decode([SettingsPreset].self, from: data)
    else { return [] }

    return presets.map { SettingsProfileEntity(id: $0.id, name: $0.name) }
}
