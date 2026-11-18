//
//  RideCheckpointStore.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// The ride so far, saved every few minutes so a crash or a killed app
/// leaves a held ride behind instead of nothing.
enum RideCheckpointStore {
    private static var trackURL: URL {
        ConnectivityManager.ridesDirectory.appendingPathComponent("checkpoint.track")
    }
    private static var metaURL: URL {
        ConnectivityManager.ridesDirectory.appendingPathComponent("checkpoint.json")
    }

    static var exists: Bool {
        let fm = FileManager.default
        return fm.fileExists(atPath: metaURL.path) && fm.fileExists(atPath: trackURL.path)
    }

    /// Writes off the main queue. `onSaved` runs on main once both files are written.
    static func save(
        _ summary: RideSummary, locations: [CLLocation], heartRates: [Double?], powers: [Double?],
        onSaved: @escaping () -> Void
    ) {
        let trackData = TrackEncoder.encodeV5(locations, heartRates: heartRates, powers: powers)
        let metaData = try? JSONEncoder().encode(CheckpointMeta(summary))
        let trackURL = Self.trackURL
        let metaURL = Self.metaURL

        DispatchQueue.global(qos: .utility).async {
            do {
                try trackData.write(to: trackURL, options: .atomic)
            } catch {
                print("[Checkpoint] Failed to write track: \(error)")
                return
            }
            guard let metaData else { return }
            do {
                try metaData.write(to: metaURL, options: .atomic)
            } catch {
                print("[Checkpoint] Failed to write meta: \(error)")
                return
            }
            DispatchQueue.main.async { onSaved() }
        }
    }

    static func delete() {
        try? FileManager.default.removeItem(at: trackURL)
        try? FileManager.default.removeItem(at: metaURL)
    }

    /// Copies the checkpoint's track to where a held ride keeps it and returns
    /// the held ride. Run off the main queue. A checkpoint that can't be read
    /// is deleted and returns nil.
    static func recover() -> (summary: RideSummary, trackURL: URL)? {
        guard let metaData = try? Data(contentsOf: metaURL),
            let meta = try? JSONDecoder().decode(CheckpointMeta.self, from: metaData)
        else {
            print("[Checkpoint] Could not decode meta, discarding")
            delete()
            return nil
        }

        guard let trackData = try? Data(contentsOf: trackURL), !trackData.isEmpty else {
            print("[Checkpoint] Empty track data, discarding")
            delete()
            return nil
        }

        let trackFilename = "\(meta.rideID.uuidString).track"
        let destURL = ConnectivityManager.ridesDirectory.appendingPathComponent(trackFilename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: trackURL, to: destURL)
        } catch {
            print("[Checkpoint] Failed to copy track: \(error)")
            delete()
            return nil
        }

        let summary = RideSummary(
            id: meta.rideID,
            name: meta.name,
            activityType: meta.activityType,
            date: meta.startDate,
            elapsedTime: meta.elapsedTime,
            movingTime: meta.movingTime,
            distance: meta.distance,
            calories: meta.calories,
            elevationGain: meta.elevationGain,
            elevationLoss: meta.elevationLoss,
            avgSpeed: meta.avgSpeed,
            pointCount: meta.pointCount,
            trackFilename: trackFilename,
            maxSpeed: meta.maxSpeed > 0 ? meta.maxSpeed : nil,
            avgPower: meta.avgPower,
            maxPower: meta.maxPower,
            avgHeartRate: meta.avgHeartRate,
            maxHeartRate: meta.maxHeartRate,
            highestElevation: meta.highestElevation,
            lowestElevation: meta.lowestElevation,
            isOnHold: true,
            splitProgress: meta.splitProgress
        )
        return (summary, destURL)
    }
}

/// `checkpoint.json`. Field names are the file format, so renaming one
/// breaks recovery of a checkpoint written by an older build.
private struct CheckpointMeta: Codable, Sendable {
    let rideID: UUID
    let startDate: Date
    let name: String
    let activityType: ActivityType
    let distance: Double
    let movingTime: TimeInterval
    let elapsedTime: TimeInterval
    let calories: Double
    let elevationGain: Double
    let elevationLoss: Double
    let avgSpeed: Double
    let maxSpeed: Double
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let avgPower: Double?
    let maxPower: Double?
    let highestElevation: Double?
    let lowestElevation: Double?
    let pointCount: Int
    let splitProgress: SplitProgress?

    init(_ summary: RideSummary) {
        rideID = summary.id
        startDate = summary.date
        name = summary.name
        activityType = summary.activityType
        distance = summary.distance
        movingTime = summary.movingTime
        elapsedTime = summary.elapsedTime
        calories = summary.calories
        elevationGain = summary.elevationGain
        elevationLoss = summary.elevationLoss
        avgSpeed = summary.avgSpeed
        maxSpeed = summary.maxSpeed ?? 0
        avgHeartRate = summary.avgHeartRate
        maxHeartRate = summary.maxHeartRate
        avgPower = summary.avgPower
        maxPower = summary.maxPower
        highestElevation = summary.highestElevation
        lowestElevation = summary.lowestElevation
        pointCount = summary.pointCount
        splitProgress = summary.splitProgress
    }
}
