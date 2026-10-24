//
//  PresetIntents.swift
//  OG Bike Computer
//
//  App Intents for selecting settings presets and bikes.
//

import AppIntents
import Foundation

// MARK: - Select Settings Preset

struct SelectSettingsPresetIntent: AppIntent {
    static var title: LocalizedStringResource = "Select Settings Preset"
    static var description: IntentDescription = "Switches to a different settings preset."

    @Parameter(title: "Preset")
    var preset: SettingsPresetEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let store = UserSettingsStore()
            store.switchToPreset(id: preset.id)
        }
        return .result(dialog: "Switched to \(preset.name) preset.")
    }
}

// MARK: - Select Bike

struct SelectBikeIntent: AppIntent {
    static var title: LocalizedStringResource = "Select Bike"
    static var description: IntentDescription = "Switches to a different bike."

    @Parameter(title: "Bike")
    var bike: BikeEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let store = UserSettingsStore()
            store.settings.activeBikeID = bike.id
        }
        return .result(dialog: "Switched to \(bike.name).")
    }
}
