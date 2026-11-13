//
//  GetSettingIntent.swift
//  OG Bike Computer
//
//  Reads a setting so a shortcut can branch on it, e.g. a toggle built from
//  Get Setting, If, and Change Setting.
//

// Phone only: the watch keeps its settings elsewhere, so this would read stale values there.
#if os(iOS) && !WIDGET_EXTENSION
import AppIntents
import Foundation

struct GetSettingIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Setting"
    static var description: IntentDescription = "Returns the current value of a ride setting, so a shortcut can check it before changing it."

    @Parameter(title: "Setting")
    var setting: ChangeableSetting

    func perform() async throws -> some IntentResult & ReturnsValue<SettingValue> & ProvidesDialog {
        let value = await MainActor.run { currentValue(in: UserSettingsStore.shared.settings) }
        return .result(value: value, dialog: "\(setting.spokenName) is \(value.spokenName).")
    }

    private func currentValue(in settings: UserSettings) -> SettingValue {
        switch setting {
        case .autoPause:
            return settings.ridePreferences.autoPause.enabled ? .on : .off
        case .mapRotation:
            return settings.ridePreferences.mapRotation == .headingUp ? .headingUp : .northUp
        case .units:
            return settings.unitPreferences.distance == .miles ? .imperial : .metric
        case .voiceAlerts:
            switch settings.navigationAlerts.turnAlerts.defaultMode {
            case .voiceAndHaptic: return .voiceAndHaptic
            case .voiceOnly:      return .voiceOnly
            case .hapticOnly:     return .hapticOnly
            case .none:           return .none
            }
        }
    }
}
#endif
