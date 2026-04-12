//
//  ChangeSettingIntent.swift
//  OG Bike Computer
//
//  Allows Siri/Shortcuts to change individual settings mid-ride.
//  Changes are tracked so the user can revert them after the ride.
//

import AppIntents
import Foundation

// MARK: - Changeable Settings Enum

enum ChangeableSetting: String, AppEnum, CaseIterable {
    case autoPause
    case mapRotation
    case units
    case voiceAlerts

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Setting")

    static var caseDisplayRepresentations: [ChangeableSetting: DisplayRepresentation] = [
        .autoPause: "Auto-Pause",
        .mapRotation: "Map Rotation",
        .units: "Units",
        .voiceAlerts: "Voice Alerts"
    ]
}

enum SettingValue: String, AppEnum, CaseIterable {
    case on
    case off
    case headingUp
    case northUp
    case imperial
    case metric
    case voiceAndHaptic
    case voiceOnly
    case hapticOnly
    case none

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Value")

    static var caseDisplayRepresentations: [SettingValue: DisplayRepresentation] = [
        .on: "On",
        .off: "Off",
        .headingUp: "Heading Up",
        .northUp: "North Up",
        .imperial: "Imperial",
        .metric: "Metric",
        .voiceAndHaptic: "Voice and Haptic",
        .voiceOnly: "Voice Only",
        .hapticOnly: "Haptic Only",
        .none: "None"
    ]
}

// MARK: - Change Setting Intent

struct ChangeSettingIntent: AppIntent {
    static var title: LocalizedStringResource = "Change Setting"
    static var description: IntentDescription = "Changes a ride setting. Mid-ride changes are temporary and can be reverted after the ride."

    @Parameter(title: "Setting")
    var setting: ChangeableSetting

    @Parameter(title: "Value")
    var value: SettingValue

    func perform() async throws -> some IntentResult & ProvidesDialog {
        await MainActor.run {
            let store = UserSettingsStore()

            switch setting {
            case .autoPause:
                let original = store.settings.ridePreferences.autoPause.enabled
                store.trackRideChange(key: "autoPause", original: original)
                store.settings.ridePreferences.autoPause.enabled = (value == .on)

            case .mapRotation:
                let original = store.settings.ridePreferences.mapRotation.rawValue
                store.trackRideChange(key: "mapRotation", original: original)
                if value == .headingUp {
                    store.settings.ridePreferences.mapRotation = .headingUp
                } else if value == .northUp {
                    store.settings.ridePreferences.mapRotation = .northUp
                }

            case .units:
                let original = store.settings.unitPreferences.distance.rawValue
                store.trackRideChange(key: "units", original: original)
                if value == .imperial {
                    store.settings.unitPreferences = .imperial
                } else if value == .metric {
                    store.settings.unitPreferences = .metric
                }

            case .voiceAlerts:
                let original = store.settings.navigationAlerts.turnAlerts.defaultMode.rawValue
                store.trackRideChange(key: "voiceAlerts", original: original)
                switch value {
                case .voiceAndHaptic:
                    store.settings.navigationAlerts.turnAlerts.defaultMode = .voiceAndHaptic
                case .voiceOnly:
                    store.settings.navigationAlerts.turnAlerts.defaultMode = .voiceOnly
                case .hapticOnly:
                    store.settings.navigationAlerts.turnAlerts.defaultMode = .hapticOnly
                case .off, .none:
                    store.settings.navigationAlerts.turnAlerts.defaultMode = .none
                default:
                    break
                }
            }
        }

        return .result(dialog: "Changed \(setting.rawValue) to \(value.rawValue).")
    }
}
