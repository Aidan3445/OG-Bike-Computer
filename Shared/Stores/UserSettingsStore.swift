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
        unitPreferences: .imperial
    )

    private enum CodingKeys: String, CodingKey {
        case riderWeight, riderHeight, bikes, activeBikeID, unitPreferences
    }

    init(riderWeight: Double, riderHeight: Double, bikes: [BikePreset], activeBikeID: UUID?, unitPreferences: UnitPreferences = .imperial) {
        self.riderWeight = riderWeight
        self.riderHeight = riderHeight
        self.bikes = bikes
        self.activeBikeID = activeBikeID
        self.unitPreferences = unitPreferences
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        riderWeight = try container.decode(Double.self, forKey: .riderWeight)
        riderHeight = try container.decode(Double.self, forKey: .riderHeight)
        bikes = try container.decode([BikePreset].self, forKey: .bikes)
        activeBikeID = try container.decodeIfPresent(UUID.self, forKey: .activeBikeID)
        unitPreferences = try container.decodeIfPresent(UnitPreferences.self, forKey: .unitPreferences) ?? .default
    }
}

// MARK: - Store

class UserSettingsStore: ObservableObject {
    @Published var settings: UserSettings

    private let fileURL: URL
    private var cancellables = Set<AnyCancellable>()

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("userSettings.json")

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

        // Debounce disk writes and watch sync to avoid flooding I/O and WCSession traffic
        // while the user is actively editing text fields.
        $settings
            .dropFirst()
            .debounce(for: .seconds(0.5), scheduler: DispatchQueue.main)
            .sink { [weak self] _ in
                self?.save()
                self?.sendToWatch()
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
}
