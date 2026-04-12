//
//  ProfileIntents.swift
//  OG Bike Computer
//
//  App Intents for selecting settings profiles and bikes.
//

import AppIntents
import Foundation

// MARK: - Select Settings Profile

struct SelectSettingsProfileIntent: AppIntent {
    static var title: LocalizedStringResource = "Select Settings Profile"
    static var description: IntentDescription = "Switches to a different settings profile."

    @Parameter(title: "Profile")
    var profile: SettingsProfileEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let store = UserSettingsStore()
            store.switchToProfile(id: profile.id)
        }
        return .result(dialog: "Switched to \(profile.name) profile.")
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
