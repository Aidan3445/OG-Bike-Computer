//
//  IntegrationSettingsStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import Combine

class IntegrationSettingsStore: ObservableObject {
    @Published var settings: IntegrationSettings

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("integrationSettings.json")

        if let data = try? Data(contentsOf: fileURL),
           let loaded = try? JSONDecoder().decode(IntegrationSettings.self, from: data) {
            settings = loaded
        } else {
            settings = .default
        }

        $settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
            }
            .store(in: &cancellables)
    }

    /// Migrate healthKitAutoUpload from IntegrationSettings → UserSettings (one-time).
    func migrateHealthKitSetting(to userSettings: UserSettingsStore) {
        if let legacy = settings.healthKitAutoUpload {
            userSettings.settings.healthKitAutoUpload = legacy
            settings.healthKitAutoUpload = nil
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(settings) {
            try? data.write(to: fileURL, options: .atomic)
        }
    }

    func disconnect(service: IntegrationServiceID) {
        var config = settings.config(for: service)
        config.isConnected = false
        config.importRoutes = false
        config.autoUpload = false
        settings.setConfig(config, for: service)
        KeychainHelper.deleteTokens(for: service)
    }
}
