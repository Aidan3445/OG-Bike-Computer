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
        loadAll()
    }

    func save(_ ride: RideSummary) {
        let fileURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        if let data = try? JSONEncoder().encode(ride) {
            try? data.write(to: fileURL)
        }
        if !rides.contains(where: { $0.id == ride.id }) {
            rides.insert(ride, at: 0)
        }
    }

    func delete(_ ride: RideSummary) {
        let jsonURL = directory.appendingPathComponent("\(ride.id.uuidString).json")
        try? FileManager.default.removeItem(at: jsonURL)

        let trackURL = directory.appendingPathComponent(ride.trackFilename)
        try? FileManager.default.removeItem(at: trackURL)

        rides.removeAll { $0.id == ride.id }
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
            print("GPX export error: \(error)")
            return nil
        }
    }

    func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil) else { return }

        rides = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(RideSummary.self, from: data)
            }
            .sorted { $0.date > $1.date }
    }
}
