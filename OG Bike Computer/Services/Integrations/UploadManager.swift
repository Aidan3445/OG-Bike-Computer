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
        resumeInProgressUploads()
    }

    /// Minimum distance for Strava auto-upload (0.1 miles in meters).
    /// Rides below this threshold are saved locally but not auto-uploaded.
    /// The user can still upload manually from ride details.
    private static let minAutoUploadDistance: Double = 0.1 * 1609.34 // ~161m

    /// Called when a new ride arrives from the watch. Checks auto-upload settings and uploads.
    func handleNewRide(_ ride: RideSummary) {
        guard let settings = integrationSettings?.settings else { return }

        // Only Strava supports auto-upload
        guard settings.config(for: .strava).autoUpload else { return }

        // Skip auto-upload for very short rides (manual upload still available)
        guard ride.distance >= Self.minAutoUploadDistance else {
            logger.info("[UploadManager] Ride too short (\(String(format: "%.0f", ride.distance))m) for auto-upload, skipping Strava")
            RideNotificationManager.shared.postShortRideSkipped(ride)
            return
        }

        Task {
            await uploadToStrava(ride)
        }
    }

    private func uploadToStrava(_ ride: RideSummary) async {
        guard let rideStore else { return }
        let rideID = ride.id

        // 1. In-memory lock: prevent concurrent uploads of the same ride
        let alreadyPending = await MainActor.run { pendingUploads.contains(rideID) }
        if alreadyPending {
            logger.info("[UploadManager] Upload already in progress for \(ride.name), skipping")
            return
        }

        // 2. Check for existing Strava upload record
        // Use the latest state from the store (not the passed-in ride) to catch
        // retransmits where the watch version has uploads: nil
        let latestRide = await MainActor.run { rideStore.rides.first(where: { $0.id == rideID }) }
        let uploads = latestRide?.uploads ?? ride.uploads
        if let existing = uploads?.first(where: { $0.service == .strava }) {
            if existing.isComplete {
                logger.info("[UploadManager] Ride \(ride.name) already uploaded to Strava, skipping")
                return
            }

            // 3. Resume in-progress upload (has uploadId but no activityID yet)
            if let uploadId = existing.uploadId {
                _ = await MainActor.run { pendingUploads.insert(rideID) }
                defer { Task { @MainActor in pendingUploads.remove(rideID) } }

                do {
                    let result = try await stravaClient.pollUpload(uploadID: uploadId)
                    await MainActor.run {
                        completeUploadRecord(uploadId: uploadId, activityID: result.activityID, webURL: result.webURL, for: rideID)
                    }
                    logger.info("[UploadManager] Resumed upload for \(ride.name): \(result.activityID)")
                } catch {
                    logger.error("[UploadManager] Resume failed for \(ride.name): \(error.localizedDescription)")
                    saveFailedUpload(rideID: rideID, service: .strava)
                }
                return
            }
        }

        // 4. Fresh upload
        _ = await MainActor.run { pendingUploads.insert(rideID) }
        defer { Task { @MainActor in pendingUploads.remove(rideID) } }

        guard let gpxURL = rideStore.exportGPX(for: ride),
              let gpxData = try? Data(contentsOf: gpxURL) else {
            logger.error("[UploadManager] Failed to export GPX for ride: \(ride.name)")
            return
        }

        do {
            // 4a. POST upload — get uploadId + partial record
            let (uploadId, partialRecord) = try await stravaClient.startUpload(gpxData: gpxData, name: ride.name, externalId: rideID.uuidString)

            // 4b. Persist partial record immediately (crash-safe)
            await MainActor.run {
                appendUploadRecord(partialRecord, to: rideID)
            }

            // 4c. Poll for completion
            let result = try await stravaClient.pollUpload(uploadID: uploadId)

            // 4d. Complete the record with activityID
            await MainActor.run {
                completeUploadRecord(uploadId: uploadId, activityID: result.activityID, webURL: result.webURL, for: rideID)
            }
            logger.info("[UploadManager] Uploaded \(ride.name) to Strava: \(result.activityID)")
        } catch {
            logger.error("[UploadManager] Strava upload failed for \(ride.name): \(error.localizedDescription)")
            saveFailedUpload(rideID: rideID, service: .strava)
        }
    }

    /// Manually upload a ride to Strava (from the share menu)
    func manualUploadToStrava(_ ride: RideSummary) async throws -> ServiceUploadRecord {
        guard let rideStore else { throw ServiceError.noData }
        let rideID = ride.id

        // Check for existing complete upload
        if let existing = ride.uploads?.first(where: { $0.service == .strava && $0.isComplete }) {
            return existing
        }

        // Resume in-progress upload if one exists
        if let existing = ride.uploads?.first(where: { $0.service == .strava }),
           let uploadId = existing.uploadId {
            let result = try await stravaClient.pollUpload(uploadID: uploadId)
            await MainActor.run {
                completeUploadRecord(uploadId: uploadId, activityID: result.activityID, webURL: result.webURL, for: rideID)
            }
            return ServiceUploadRecord(
                service: .strava,
                remoteID: "\(result.activityID)",
                uploadedAt: Date(),
                webURL: result.webURL,
                uploadId: uploadId
            )
        }

        // Fresh upload
        guard let gpxURL = rideStore.exportGPX(for: ride),
              let gpxData = try? Data(contentsOf: gpxURL) else {
            throw ServiceError.noData
        }

        let (uploadId, partialRecord) = try await stravaClient.startUpload(gpxData: gpxData, name: ride.name, externalId: rideID.uuidString)

        await MainActor.run {
            appendUploadRecord(partialRecord, to: rideID)
        }

        let result = try await stravaClient.pollUpload(uploadID: uploadId)

        await MainActor.run {
            completeUploadRecord(uploadId: uploadId, activityID: result.activityID, webURL: result.webURL, for: rideID)
        }

        return ServiceUploadRecord(
            service: .strava,
            remoteID: "\(result.activityID)",
            uploadedAt: Date(),
            webURL: result.webURL,
            uploadId: uploadId
        )
    }

    private func appendUploadRecord(_ record: ServiceUploadRecord, to rideID: UUID) {
        guard let rideStore,
              let index = rideStore.rides.firstIndex(where: { $0.id == rideID }) else { return }

        var ride = rideStore.rides[index]
        var uploads = ride.uploads ?? []
        // Don't duplicate — match on service + uploadId
        if !uploads.contains(where: { $0.service == record.service && $0.uploadId == record.uploadId }) {
            uploads.append(record)
            ride.uploads = uploads
            rideStore.rides[index] = ride
            persistRide(ride, rideID: rideID)
        }
    }

    private func completeUploadRecord(uploadId: Int, activityID: Int, webURL: String, for rideID: UUID) {
        guard let rideStore,
              let rideIndex = rideStore.rides.firstIndex(where: { $0.id == rideID }) else { return }

        var ride = rideStore.rides[rideIndex]
        guard var uploads = ride.uploads,
              let uploadIndex = uploads.firstIndex(where: { $0.uploadId == uploadId && $0.service == .strava }) else { return }

        uploads[uploadIndex].remoteID = "\(activityID)"
        uploads[uploadIndex].webURL = webURL
        uploads[uploadIndex].uploadedAt = Date()
        ride.uploads = uploads
        rideStore.rides[rideIndex] = ride
        persistRide(ride, rideID: rideID)
    }

    private func persistRide(_ ride: RideSummary, rideID: UUID) {
        guard let rideStore else { return }
        let fileURL = rideStore.directory.appendingPathComponent("\(rideID.uuidString).json")
        if let data = try? JSONEncoder().encode(ride) {
            try? data.write(to: fileURL, options: .atomic)
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
            // Only skip if a complete upload already exists for this service
            if let existing = ride.uploads?.first(where: { $0.service == entry.service }),
               existing.isComplete { continue }

            switch entry.service {
            case .strava:
                Task { await uploadToStrava(ride) }
            case .rideWithGPS, .fitness:
                break // No API upload support
            }
        }
    }

    /// Resume any uploads that were started (have uploadId) but not completed (no remoteID).
    private func resumeInProgressUploads() {
        guard let rideStore else { return }
        for ride in rideStore.rides {
            guard let uploads = ride.uploads else { continue }
            let hasIncomplete = uploads.contains(where: { $0.service == .strava && !$0.isComplete && $0.uploadId != nil })
            if hasIncomplete {
                Task { await uploadToStrava(ride) }
            }
        }
    }
}

private struct FailedUpload: Codable {
    let rideID: UUID
    let service: IntegrationServiceID
    let failedAt: Date
}
