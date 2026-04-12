//
//  UserSettingsStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import Foundation
import Combine
import SwiftUI

// MARK: - Bike Preset

struct BikePreset: Codable, Identifiable, Equatable {
    var id: UUID
    var name: String
    var weight: Double // kg

    init(id: UUID = UUID(), name: String, weight: Double) {
        self.id = id
        self.name = name
        self.weight = weight
    }
}

// MARK: - User Settings

struct UserSettings: Codable, Equatable {
    var riderWeight: Double   // kg
    var riderHeight: Double   // cm
    var bikes: [BikePreset]
    var activeBikeID: UUID?
    var unitPreferences: UnitPreferences
    var navigationAlerts: NavigationAlertPreferences
    var ridePreferences: RidePreferences
    var phoneAlerts: PhoneAlertPreferences
    var healthKitAutoUpload: Bool

    /// Active bike weight, or a manual fallback
    var bikeWeight: Double {
        if let id = activeBikeID, let bike = bikes.first(where: { $0.id == id }) {
            return bike.weight
        }
        return bikes.first?.weight ?? 10
    }

    var activeBikeName: String {
        if let id = activeBikeID, let bike = bikes.first(where: { $0.id == id }) {
            return bike.name
        }
        return bikes.first?.name ?? "No bike"
    }

    var totalMass: Double { riderWeight + bikeWeight }

    static let `default` = UserSettings(
        riderWeight: 75,
        riderHeight: 175,
        bikes: [
            BikePreset(name: "My Bike", weight: 10)
        ],
        activeBikeID: nil,  // will use first bike
        unitPreferences: .imperial,
        navigationAlerts: .default,
        ridePreferences: .default,
        phoneAlerts: .default,
        healthKitAutoUpload: true
    )

    private enum CodingKeys: String, CodingKey {
        case riderWeight, riderHeight, bikes, activeBikeID, unitPreferences, navigationAlerts, ridePreferences, phoneAlerts, healthKitAutoUpload
    }

    init(riderWeight: Double, riderHeight: Double, bikes: [BikePreset], activeBikeID: UUID?, unitPreferences: UnitPreferences = .imperial, navigationAlerts: NavigationAlertPreferences = .default, ridePreferences: RidePreferences = .default, phoneAlerts: PhoneAlertPreferences = .default, healthKitAutoUpload: Bool = true) {
        self.riderWeight = riderWeight
        self.riderHeight = riderHeight
        self.bikes = bikes
        self.activeBikeID = activeBikeID
        self.unitPreferences = unitPreferences
        self.navigationAlerts = navigationAlerts
        self.ridePreferences = ridePreferences
        self.phoneAlerts = phoneAlerts
        self.healthKitAutoUpload = healthKitAutoUpload
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        riderWeight = try container.decode(Double.self, forKey: .riderWeight)
        riderHeight = try container.decode(Double.self, forKey: .riderHeight)
        bikes = try container.decode([BikePreset].self, forKey: .bikes)
        activeBikeID = try container.decodeIfPresent(UUID.self, forKey: .activeBikeID)
        unitPreferences = try container.decodeIfPresent(UnitPreferences.self, forKey: .unitPreferences) ?? .default
        navigationAlerts = try container.decodeIfPresent(NavigationAlertPreferences.self, forKey: .navigationAlerts) ?? .default
        ridePreferences = try container.decodeIfPresent(RidePreferences.self, forKey: .ridePreferences) ?? .default
        phoneAlerts = try container.decodeIfPresent(PhoneAlertPreferences.self, forKey: .phoneAlerts) ?? .default
        healthKitAutoUpload = try container.decodeIfPresent(Bool.self, forKey: .healthKitAutoUpload) ?? true
    }
}

// MARK: - Store

class UserSettingsStore: ObservableObject {
    @Published var settings: UserSettings
    @Published var presets: [SettingsPreset] = []
    @Published var activePresetID: UUID?

    private(set) weak var metricConfigStore: MetricConfigStore?
    private let fileURL: URL
    private let presetsURL: URL
    private var cancellables = Set<AnyCancellable>()
    static let maxPresets = 10

    /// Name of the currently active profile (for display in navigation subtitles)
    var activeProfileName: String {
        if let id = activePresetID, let preset = presets.first(where: { $0.id == id }) {
            return preset.name
        }
        return "No Profile"
    }

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("userSettings.json")
        presetsURL = docs.appendingPathComponent("settingsPresets.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(UserSettings.self, from: data) {
            settings = loaded
        } else {
            settings = .default
        }

        // Ensure activeBikeID points to a real bike
        if settings.activeBikeID == nil, let first = settings.bikes.first {
            settings.activeBikeID = first.id
        }

        // Load presets
        if let data = try? Data(contentsOf: presetsURL),
           let loaded = try? JSONDecoder().decode([SettingsPreset].self, from: data) {
            presets = loaded
        }

        // Load persisted active preset ID
        if let idString = UserDefaults.standard.string(forKey: "activePresetID"),
           let id = UUID(uuidString: idString),
           presets.contains(where: { $0.id == id }) {
            activePresetID = id
        }

        // Create default "Main" profile on first launch
        if presets.isEmpty {
            let main = SettingsPreset(name: "Main", settings: settings)
            presets = [main]
            activePresetID = main.id
            savePresets()
        }

        // If no active preset but presets exist, activate the first one
        if activePresetID == nil, let first = presets.first {
            activePresetID = first.id
            persistActivePresetID()
        }

        // Debounce disk writes, watch sync, and auto-save to active profile
        $settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
                self?.sendToWatch()
                self?.autoSaveToActivePreset()
            }
            .store(in: &cancellables)
    }

    /// Attach the MetricConfigStore so metric pages are included in profile auto-save.
    /// Call this once after both stores are initialized.
    func attachMetricStore(_ store: MetricConfigStore) {
        self.metricConfigStore = store

        // Observe metric config changes for auto-save
        store.$config
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.autoSaveToActivePreset()
            }
            .store(in: &cancellables)
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func applyFromRemote(_ data: Data) {
        guard let decoded = try? JSONDecoder().decode(UserSettings.self, from: data) else { return }
        DispatchQueue.main.async {
            self.settings = decoded
        }
    }

    func sendToWatch() {
        #if os(iOS)
        guard let data = try? JSONEncoder().encode(settings) else { return }
        ConnectivityManager.shared.sendUserSettings(data)
        #endif
    }

    // MARK: - Profiles

    /// Auto-save current settings + metric config to the active profile.
    /// Called automatically on every debounced settings or metric config change.
    private func autoSaveToActivePreset() {
        guard let id = activePresetID,
              let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].settings = settings
        if let config = metricConfigStore?.config {
            presets[idx].metricConfig = config
        }
        savePresets()
    }

    /// Create a new profile from the current settings and activate it.
    func createFromCurrent(name: String) -> Bool {
        guard presets.count < Self.maxPresets else { return false }
        let preset = SettingsPreset(
            name: name,
            settings: settings,
            metricConfig: metricConfigStore?.config ?? .default
        )
        presets.append(preset)
        activePresetID = preset.id
        persistActivePresetID()
        savePresets()
        return true
    }

    /// Create a new profile from default settings and activate it.
    func createFromDefaults(name: String) -> Bool {
        guard presets.count < Self.maxPresets else { return false }
        let preset = SettingsPreset(name: name, settings: .default, metricConfig: .default)
        presets.append(preset)
        activePresetID = preset.id
        persistActivePresetID()
        // Apply default settings (preserve rider profile)
        let currentProfile = (settings.riderWeight, settings.riderHeight, settings.bikes)
        settings = .default
        settings.riderWeight = currentProfile.0
        settings.riderHeight = currentProfile.1
        settings.bikes = currentProfile.2
        if let first = settings.bikes.first { settings.activeBikeID = first.id }
        metricConfigStore?.config = .default
        savePresets()
        return true
    }

    /// Switch to a different profile. Auto-saves current profile first, then loads the target.
    func switchToProfile(id: UUID) {
        guard let preset = presets.first(where: { $0.id == id }),
              id != activePresetID else { return }

        // Auto-save current profile before switching
        autoSaveToActivePreset()

        // Load the target profile — preserve rider list (weight, height, bikes) but restore activeBikeID
        let currentProfile = (settings.riderWeight, settings.riderHeight, settings.bikes)
        settings = preset.settings
        settings.riderWeight = currentProfile.0
        settings.riderHeight = currentProfile.1
        settings.bikes = currentProfile.2
        // Restore which bike was active in this profile (if it still exists)
        if let bikeID = preset.settings.activeBikeID,
           settings.bikes.contains(where: { $0.id == bikeID }) {
            settings.activeBikeID = bikeID
        }

        // Load metric config
        metricConfigStore?.config = preset.metricConfig

        activePresetID = id
        persistActivePresetID()
    }

    func deletePreset(id: UUID) {
        presets.removeAll { $0.id == id }
        if activePresetID == id {
            // Activate the first remaining profile
            activePresetID = presets.first?.id
            persistActivePresetID()
        }
        savePresets()
    }

    func renamePreset(id: UUID, name: String) {
        guard let idx = presets.firstIndex(where: { $0.id == id }) else { return }
        presets[idx].name = name
        savePresets()
    }

    private func savePresets() {
        if let data = try? JSONEncoder().encode(presets) {
            try? data.write(to: presetsURL, options: .atomic)
        }
    }

    private func persistActivePresetID() {
        if let id = activePresetID {
            UserDefaults.standard.set(id.uuidString, forKey: "activePresetID")
        } else {
            UserDefaults.standard.removeObject(forKey: "activePresetID")
        }
    }

    // MARK: - Temporary Ride Setting Changes

    /// Dictionary of original values keyed by setting name, persisted in UserDefaults
    /// so it survives across Siri intent invocations during a ride.
    @Published var rideSettingChanges: [String: String]? {
        didSet { persistRideChanges() }
    }

    var hasUnsavedRideChanges: Bool {
        guard let changes = rideSettingChanges else { return false }
        return !changes.isEmpty
    }

    /// Record the original value before a mid-ride change (only first change per key is tracked).
    func trackRideChange(key: String, original: Any) {
        if rideSettingChanges == nil {
            rideSettingChanges = [:]
        }
        // Only track the first change so we have the true original
        if rideSettingChanges?[key] == nil {
            rideSettingChanges?[key] = String(describing: original)
        }
    }

    private func persistRideChanges() {
        if let changes = rideSettingChanges,
           let data = try? JSONEncoder().encode(changes) {
            UserDefaults.standard.set(data, forKey: "rideSettingChanges")
        } else {
            UserDefaults.standard.removeObject(forKey: "rideSettingChanges")
        }
    }

    /// Load any persisted ride changes (call on init to restore state after app relaunch).
    func loadPersistedRideChanges() {
        if let data = UserDefaults.standard.data(forKey: "rideSettingChanges"),
           let changes = try? JSONDecoder().decode([String: String].self, from: data) {
            rideSettingChanges = changes
        }
    }

    /// Revert all mid-ride changes to their original values and clear tracking.
    func revertRideChanges() {
        guard let changes = rideSettingChanges else { return }

        for (key, originalValue) in changes {
            switch key {
            case "autoPause":
                settings.ridePreferences.autoPause.enabled = (originalValue == "true")
            case "mapRotation":
                if let rotation = MapRotation(rawValue: originalValue) {
                    settings.ridePreferences.mapRotation = rotation
                }
            case "units":
                if originalValue == "miles" {
                    settings.unitPreferences = .imperial
                } else {
                    settings.unitPreferences = .metric
                }
            case "voiceAlerts":
                if let mode = AlertMode(rawValue: originalValue) {
                    settings.navigationAlerts.turnAlerts.defaultMode = mode
                }
            default:
                break
            }
        }

        rideSettingChanges = nil
    }

    /// Clear tracking without reverting (user chose to keep changes).
    func clearRideTracking() {
        rideSettingChanges = nil
    }
}
