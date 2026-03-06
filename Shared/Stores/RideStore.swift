//
//  RideStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import Combine

class RideStore: ObservableObject {
    @Published var rides: [RideSummary] = []
    let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("rides", isDirectory: true)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        print("[RideStore] directory: \(directory.path)")
        loadAll()
        printDiskContents()
    }

    func save(_ ride: RideSummary) {
        let fileURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        if let data = try? JSONEncoder().encode(ride) {
            try? data.write(to: fileURL)
            print("[RideStore] saved summary: \(ride.name) → \(fileURL.lastPathComponent)")
        } else {
            print("[RideStore] ERROR: failed to encode ride: \(ride.name)")
        }
        if !rides.contains(where: { $0.id == ride.id }) {
            rides.insert(ride, at: 0)
            print("[RideStore] added to in-memory list (now \(rides.count) rides)")
        }
    }

    func delete(_ ride: RideSummary) {
        let jsonURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)
        let trackURL = directory.appendingPathComponent(ride.trackFilename)
        try? FileManager.default.removeItem(at: trackURL)
        rides.removeAll { $0.id == ride.id }
        print("[RideStore] deleted: \(ride.name)")
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
        let points = TrackEncoder.decode(data)
        let locations = TrackEncoder.toLocations(points)
        let gpxString = GPXExporter.export(
            name: ride.name,
            locations: locations,
            activityType: ride.activityType.rawValue)
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
            print("[RideStore] GPX export error: \(error)")
            return nil
        }
    }

    func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else {
            print("[RideStore] loadAll: could not list directory")
            return
        }

        let jsonFiles = files.filter { $0.pathExtension == "json" }
        print("[RideStore] loadAll: found \(jsonFiles.count) JSON files, \(files.count) total files")

        rides = jsonFiles
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else {
                    print("[RideStore] loadAll: could not read \(url.lastPathComponent)")
                    return nil
                }
                guard let ride = try? JSONDecoder().decode(RideSummary.self, from: data) else {
                    print("[RideStore] loadAll: could not decode \(url.lastPathComponent)")
                    return nil
                }
                return ride
            }
            .sorted { $0.date > $1.date }

        print("[RideStore] loadAll: loaded \(rides.count) rides")
        for ride in rides {
            let trackExists = FileManager.default.fileExists(
                atPath: directory.appendingPathComponent(ride.trackFilename).path)
            print("[RideStore]   • \(ride.name) | \(ride.date) | track: \(trackExists ? "✓" : "✗ MISSING")")
        }
    }

    func printDiskContents() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else {
            print("[RideStore] printDiskContents: directory empty or unreadable")
            return
        }
        print("[RideStore] disk contents (\(files.count) files):")
        for file in files {
            let size = (try? file.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            print("[RideStore]   \(file.lastPathComponent) (\(size) bytes)")
        }
    }
}
