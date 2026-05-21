//
//  RideStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import CoreLocation
import Combine
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "RideStore")

class RideStore: ObservableObject {
    @Published var rides: [RideSummary] = []
    let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("rides", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        logger.log("[RideStore] directory: \(self.directory.path)")
        loadAll()
        printDiskContents()
    }

    func save(_ ride: RideSummary) {
        let fileURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        if let data = try? JSONEncoder().encode(ride) {
            try? data.write(to: fileURL)
            logger.log("[RideStore] saved summary: \(ride.name) → \(fileURL.lastPathComponent)")
        } else {
            logger.log("[RideStore] ERROR: failed to encode ride: \(ride.name)")
        }
        if !rides.contains(where: { $0.id == ride.id }) {
            rides.insert(ride, at: 0)
            logger.log("[RideStore] added to in-memory list (nself.ow \(self.rides.count) rides)")
        }
    }

    func delete(_ ride: RideSummary) {
        let jsonURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)
        let trackURL = directory.appendingPathComponent(ride.trackFilename)
        try? FileManager.default.removeItem(at: trackURL)
        rides.removeAll { $0.id == ride.id }
        logger.log("[RideStore] deleted: \(ride.name)")
    }

    func deleteAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
        rides.removeAll()
        logger.log("[RideStore] deleted all rides")
    }

    func update(_ ride: RideSummary) {
        let fileURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        if let data = try? JSONEncoder().encode(ride) {
            try? data.write(to: fileURL)
        }
        if let index = rides.firstIndex(where: { $0.id == ride.id }) {
            rides[index] = ride
        } else {
            rides.insert(ride, at: 0)
        }
        logger.log("[RideStore] updated: \(ride.name)")
    }

    func rename(_ ride: RideSummary, to newName: String) {
        guard let index = rides.firstIndex(where: { $0.id == ride.id }) else { return }
        var updated = ride
        updated.name = newName
        let fileURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: fileURL)
        }
        rides[index] = updated
        logger.log("[RideStore] renamed: \(newName)")
    }

    var heldRide: RideSummary? {
        rides.first { $0.onHold }
    }

    var completedRides: [RideSummary] {
        rides.filter { !$0.onHold }
    }

    var storageSize: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }
        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func trackURL(for ride: RideSummary) -> URL {
        directory.appendingPathComponent(ride.trackFilename)
    }

    func exportGPX(for ride: RideSummary) -> URL? {
        let trackURL = directory.appendingPathComponent(ride.trackFilename)
        guard let data = try? Data(contentsOf: trackURL) else { return nil }

        // Decode with extended data (v5 includes HR/power, v4 falls back gracefully)
        let v5Points = TrackEncoder.decodeV5Full(data)
        let locations = v5Points.map { pt in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon),
                altitude: pt.altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: Date(timeIntervalSince1970: pt.timestamp))
        }
        let pointExtras = v5Points.map { pt in
            GPXExporter.PointExtras(
                power: pt.power > 0 ? pt.power : nil,
                heartRate: pt.heartRate > 0 ? pt.heartRate : nil
            )
        }
        let gpxString = GPXExporter.export(
            name: ride.name,
            locations: locations,
            activityType: ride.activityType.rawValue,
            pointExtras: pointExtras)
        guard let gpxData = gpxString.data(using: .utf8) else { return nil }
        let sanitized = ride.name
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: " ", with: "_")
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(sanitized)_\(Int(ride.date.timeIntervalSince1970)).gpx")
        do {
            try gpxData.write(to: tempURL)
            return tempURL
        } catch {
            logger.log("[RideStore] GPX export error: \(error)")
            return nil
        }
    }

    func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else {
            logger.log("[RideStore] loadAll: could not list directory")
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        logger.log("[RideStore] loadAll: found \(jsonFiles.count) JSON files, \(files.count) total files")

        rides = jsonFiles
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    logger.log("[RideStore] loadAll: could not read \(url.lastPathComponent)")
                    return nil
                }
                guard let ride = try? JSONDecoder().decode(RideSummary.self, from: data) else {
                    logger.log("[RideStore] loadAll: could not decode \(url.lastPathComponent)")
                    return nil
                }
                return ride
            }
            .sorted { $0.date > $1.date }

        // Auto-discard held rides whose track was wiped by the pre-fix self-copy bug.
        // A held ride with no track is unrecoverable — Continue can't restore state and
        // End & Save can't transfer anything. Leaving it in the list just shows a
        // broken row that no action can clean up.
        let orphanedHeld = rides.filter { ride in
            guard ride.onHold else { return false }
            return !FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ride.trackFilename).path)
        }
        for ride in orphanedHeld {
            let jsonURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
            try? FileManager.default.removeItem(at: jsonURL)
            logger.log("[RideStore] auto-discarded held ride with missing track: \(ride.name)")
        }
        if !orphanedHeld.isEmpty {
            let orphanedIDs = Set(orphanedHeld.map(\.id))
            rides.removeAll { orphanedIDs.contains($0.id) }
        }

        logger.log("[RideStore] loadAll:self. loaded \(self.rides.count) rides")
        for ride in rides {
            let trackExists = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ride.trackFilename).path)
            logger.log("[RideStore]   • \(ride.name) | \(ride.date) | track: \(trackExists ? "✓" : "✗ MISSING")")
        }
    }

    func printDiskContents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            logger.log("[RideStore] printDiskContents: directory empty or unreadable")
            return
        }
        logger.log("[RideStore] disk contents (\(files.count) files):")
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            logger.log("[RideStore]   \(file.lastPathComponent) (\(size) bytes)")
        }
    }
}
