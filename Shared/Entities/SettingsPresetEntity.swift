//
//  SettingsPresetEntity.swift
//  OG Bike Computer
//
//  App Entity wrapper for SettingsPreset, enabling Shortcuts/Siri preset switching.
//

import AppIntents
import Foundation

struct SettingsPresetEntity: AppEntity {
    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Settings Preset")

    static var defaultQuery = SettingsPresetEntityQuery()

    var id: UUID
    var name: String

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)")
    }
}

struct SettingsPresetEntityQuery: EntityQuery {
    func entities(for identifiers: [UUID]) async throws -> [SettingsPresetEntity] {
        await loadPresetEntities().filter { identifiers.contains($0.id) }
    }

    func suggestedEntities() async throws -> [SettingsPresetEntity] {
        await loadPresetEntities()
    }

    func defaultResult() async -> SettingsPresetEntity? {
        let presets = await loadPresetEntities()
        let activeID = UserDefaults.standard.string(forKey: "activePresetID")
            .flatMap { UUID(uuidString: $0) }
        return presets.first { $0.id == activeID } ?? presets.first
    }
}

extension SettingsPresetEntityQuery: EntityStringQuery {
    func entities(matching string: String) async throws -> [SettingsPresetEntity] {
        let all = await loadPresetEntities()
        guard !string.isEmpty else { return all }
        return all.filter { $0.name.localizedCaseInsensitiveContains(string) }
    }
}

private func loadPresetEntities() -> [SettingsPresetEntity] {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url = docs.appendingPathComponent("settingsPresets.json")
    guard let data = try? Data(contentsOf: url),
          let presets = try? JSONDecoder().decode([SettingsPreset].self, from: data)
    else { return [] }

    return presets.map { SettingsPresetEntity(id: $0.id, name: $0.name) }
}
