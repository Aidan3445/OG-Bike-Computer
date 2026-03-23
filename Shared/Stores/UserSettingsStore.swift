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
        activeBikeID: nil  // will use first bike
    )

    private enum CodingKeys: String, CodingKey {
        case riderWeight, riderHeight, bikes, activeBikeID
    }
}

// MARK: - Store

class UserSettingsStore: ObservableObject {
    @Published var settings: UserSettings {
        didSet { save() }
    }

    private let fileURL: URL

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
