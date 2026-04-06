//
//  UploadManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import os
import Combine

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "UploadManager")

class UploadManager: ObservableObject {
    static let shared = UploadManager()

    @Published var pendingUploads: Set<UUID> = []

    private let stravaClient = StravaClient()
    private weak var rideStore: RideStore?
    private weak var integrationSettings: IntegrationSettingsStore?

    private init() {}

    func configure(rideStore: RideStore, integrationSettings: IntegrationSettingsStore) {
        self.rideStore = rideStore
        self.integrationSettings = integrationSettings
    }

    /// Called when a new ride arrives from the watch. Checks auto-upload settings and uploads.
    func handleNewRide(_ ride: RideSummary) {
        guard let settings = integrationSettings?.settings else { return }

        // Only Strava supports auto-upload
        guard settings.config(for: .strava).autoUpload else { return }

        Task {
            await uploadToStrava(ride)
        }
    }

    private func uploadToStrava(_ ride: RideSummary) async {
        guard let rideStore else { return }

        // Already uploaded — skip
        if ride.uploads?.contains(where: { $0.service == .strava }) == true {
            logger.info("[UploadManager] Ride \(ride.name) already has Strava upload, skipping")
            return
        }

        let rideID = ride.id
        _ = await MainActor.run { pendingUploads.insert(rideID) }
        defer { Task { @MainActor in pendingUploads.remove(rideID) } }

        guard let gpxURL = rideStore.exportGPX(for: ride),
              let gpxData = try? Data(contentsOf: gpxURL) else {
            logger.error("[UploadManager] Failed to export GPX for ride: \(ride.name)")
            return
        }

        do {
            let record = try await stravaClient.uploadRide(gpxData: gpxData, name: ride.name, externalId: rideID.uuidString)
            logger.info("[UploadManager] Uploaded \(ride.name) to Strava: \(record.remoteID)")

            await MainActor.run {
                appendUploadRecord(record, to: rideID)
            }
        } catch {
            logger.error("[UploadManager] Strava upload failed for \(ride.name): \(error.localizedDescription)")
            saveFailedUpload(rideID: rideID, service: .strava)
        }
    }

    /// Manually upload a ride to Strava (from the share menu)
    func manualUploadToStrava(_ ride: RideSummary) async throws -> ServiceUploadRecord {
        guard let rideStore else { throw ServiceError.noData }

        guard let gpxURL = rideStore.exportGPX(for: ride),
              let gpxData = try? Data(contentsOf: gpxURL) else {
            throw ServiceError.noData
        }

        let record = try await stravaClient.uploadRide(gpxData: gpxData, name: ride.name, externalId: ride.id.uuidString)

        await MainActor.run {
            appendUploadRecord(record, to: ride.id)
        }

        return record
    }

    private func appendUploadRecord(_ record: ServiceUploadRecord, to rideID: UUID) {
        guard let rideStore,
              let index = rideStore.rides.firstIndex(where: { $0.id == rideID }) else { return }

        var ride = rideStore.rides[index]
        var uploads = ride.uploads ?? []
        // Don't duplicate
        if !uploads.contains(where: { $0.service == record.service }) {
            uploads.append(record)
            ride.uploads = uploads
            rideStore.rides[index] = ride

            // Persist to disk
            let fileURL = rideStore.directory.appendingPathComponent("\(rideID.uuidString).json")
            if let data = try? JSONEncoder().encode(ride) {
                try? data.write(to: fileURL, options: .atomic)
            }
        }
    }

    // MARK: - Failed Upload Retry

    private let failedUploadsKey = "failedUploads"

    private func saveFailedUpload(rideID: UUID, service: IntegrationServiceID) {
        var failed = loadFailedUploads()
        let entry = FailedUpload(rideID: rideID, service: service, failedAt: Date())
        if !failed.contains(where: { $0.rideID == rideID && $0.service == service }) {
            failed.append(entry)
            if let data = try? JSONEncoder().encode(failed) {
                UserDefaults.standard.set(data, forKey: failedUploadsKey)
            }
        }
    }

    private func loadFailedUploads() -> [FailedUpload] {
        guard let data = UserDefaults.standard.data(forKey: failedUploadsKey),
              let failed = try? JSONDecoder().decode([FailedUpload].self, from: data) else {
            return []
        }
        return failed
    }

    func retryFailedUploads() {
        let failed = loadFailedUploads()
        guard !failed.isEmpty, let rideStore else { return }

        // Clear the list — successful ones won't be re-added
        UserDefaults.standard.removeObject(forKey: failedUploadsKey)

        for entry in failed {
            guard let ride = rideStore.rides.first(where: { $0.id == entry.rideID }) else { continue }
            // Only retry if already uploaded records don't include this service
            if ride.uploads?.contains(where: { $0.service == entry.service }) == true { continue }

            switch entry.service {
            case .strava:
                Task { await uploadToStrava(ride) }
            case .rideWithGPS:
                break // RWGPS doesn't support API uploads
            }
        }
    }
}

private struct FailedUpload: Codable {
    let rideID: UUID
    let service: IntegrationServiceID
    let failedAt: Date
}
