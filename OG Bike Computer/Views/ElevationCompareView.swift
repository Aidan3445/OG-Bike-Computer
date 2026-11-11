//
//  ElevationCompareView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 10/29/26.
//

#if DEBUG
import SwiftUI

/// Compares each ride's elevation gain with what Strava shows for the same
/// upload, then exports the biggest misses for offline analysis.
struct ElevationCompareView: View {
    @ObservedObject var rideStore: RideStore
    @State private var results: [UUID: StravaResult] = [:]
    @State private var selected: Set<UUID> = []
    @State private var isWorking = false
    @State private var status: String?
    @State private var shareItems: ShareItems?

    struct StravaResult: Codable {
        let activityID: String
        let gain: Double
        let elevHigh: Double?
        let elevLow: Double?
        let distance: Double
        let deviceName: String?
    }

    struct ShareItems: Identifiable {
        let id = UUID()
        let urls: [URL]
    }

    private static var folder: URL {
        DiagnosticsLog.directory.appendingPathComponent("elevation", isDirectory: true)
    }
    private static var cacheURL: URL { folder.appendingPathComponent("strava-activities.json") }

    private var stravaRides: [RideSummary] {
        rideStore.rides.filter { Self.stravaID(for: $0) != nil }
    }

    /// Biggest overcount first, rides not fetched yet last.
    private var sortedRides: [RideSummary] {
        stravaRides.sorted { a, b in
            switch (difference(a), difference(b)) {
            case let (x?, y?): return x > y
            case (_?, nil): return true
            case (nil, _?): return false
            case (nil, nil): return a.date > b.date
            }
        }
    }

    var body: some View {
        List {
            Section {
                Button {
                    Task { await fetchAll() }
                } label: {
                    Label("Fetch Strava Elevation", systemImage: "arrow.down.circle")
                }
                .disabled(isWorking || stravaRides.isEmpty)

                Button("Select 10 Biggest Misses") {
                    selected = Set(sortedRides.filter { difference($0) != nil }.prefix(10).map(\.id))
                }
                .disabled(isWorking || results.isEmpty)

                Button {
                    Task { await exportSelected() }
                } label: {
                    Label("Export \(selected.count) Selected", systemImage: "square.and.arrow.up")
                }
                .disabled(isWorking || selected.isEmpty)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if isWorking { ProgressView().controlSize(.small) }
                    Text(status ?? "\(stravaRides.count) rides uploaded to Strava, \(results.count) fetched. Fetches are cached, so a run cut short by Strava's rate limit picks up where it stopped.")
                }
            }

            Section("Rides") {
                if stravaRides.isEmpty {
                    Text("No rides with a Strava upload")
                        .foregroundStyle(.secondary)
                }
                ForEach(sortedRides) { ride in
                    row(ride)
                }
            }
        }
        .navigationTitle("Elevation vs Strava")
        .onAppear(perform: loadCache)
        .sheet(item: $shareItems) { items in
            ShareSheet(activityItems: items.urls)
        }
    }

    private func row(_ ride: RideSummary) -> some View {
        Button {
            if selected.contains(ride.id) { selected.remove(ride.id) } else { selected.insert(ride.id) }
        } label: {
            HStack(alignment: .top) {
                Image(systemName: selected.contains(ride.id) ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(selected.contains(ride.id) ? .blue : .secondary)
                VStack(alignment: .leading, spacing: 2) {
                    Text(ride.name)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(ride.date.formatted(date: .abbreviated, time: .shortened))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let strava = results[ride.id] {
                        let diff = ride.elevationGain - strava.gain
                        Text("App \(formatElevation(ride.elevationGain)) · Strava \(formatElevation(strava.gain)) · \(diff >= 0 ? "+" : "−")\(formatElevation(abs(diff)))")
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(diff > 0 ? .red : .primary)
                    } else {
                        Text("App \(formatElevation(ride.elevationGain)) · Strava not fetched")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
        .foregroundStyle(.primary)
    }

    private func difference(_ ride: RideSummary) -> Double? {
        results[ride.id].map { ride.elevationGain - $0.gain }
    }

    private static func stravaID(for ride: RideSummary) -> String? {
        ride.uploads?.first { $0.service == .strava && $0.remoteID != nil }?.remoteID
    }

    // MARK: - Fetch

    private func fetchAll() async {
        isWorking = true
        defer { isWorking = false }
        let client = StravaClient()
        let pending = stravaRides.filter { results[$0.id] == nil }
        for (index, ride) in pending.enumerated() {
            guard let id = Self.stravaID(for: ride) else { continue }
            status = "Fetching \(index + 1) of \(pending.count)…"
            do {
                let activity = try await client.fetchActivityElevation(id: id)
                results[ride.id] = StravaResult(
                    activityID: id, gain: activity.totalElevationGain,
                    elevHigh: activity.elevHigh, elevLow: activity.elevLow,
                    distance: activity.distance, deviceName: activity.deviceName)
                saveCache()
            } catch ServiceError.rateLimited {
                status = "Strava rate limit hit after \(index) rides. Try again in 15 minutes to fetch the rest."
                return
            } catch {
                status = "Stopped at \(ride.name): \(error.localizedDescription)"
                return
            }
        }
        status = "Fetched \(results.count) of \(stravaRides.count) rides."
    }

    // MARK: - Export

    /// Writes a summary of every fetched ride, plus the app's track and
    /// Strava's altitude stream for each selected ride, then shares a zip.
    private func exportSelected() async {
        isWorking = true
        defer { isWorking = false }
        let fm = FileManager.default
        try? fm.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        let client = StravaClient()

        let picks = sortedRides.filter { selected.contains($0.id) }
        for (index, ride) in picks.enumerated() {
            guard let id = Self.stravaID(for: ride) else { continue }
            status = "Exporting \(index + 1) of \(picks.count)…"
            writeTrack(for: ride)
            do {
                let streams = try await client.fetchAltitudeStreams(id: id)
                var lines = ["time,distance,altitude"]
                for i in streams.altitude.indices {
                    let t = i < streams.time.count ? streams.time[i] : .nan
                    let d = i < streams.distance.count ? streams.distance[i] : .nan
                    lines.append("\(t),\(d),\(streams.altitude[i])")
                }
                try? lines.joined(separator: "\n").write(
                    to: Self.folder.appendingPathComponent("\(ride.id.uuidString).strava.csv"),
                    atomically: true, encoding: .utf8)
            } catch ServiceError.rateLimited {
                status = "Strava rate limit hit after \(index) rides. Export again in 15 minutes."
                return
            } catch {
                status = "Stopped at \(ride.name): \(error.localizedDescription)"
                return
            }
        }
        writeSummary()

        if let zip = zipFolder() {
            shareItems = ShareItems(urls: [zip])
            status = "Exported \(picks.count) rides."
        } else {
            status = "Couldn't zip the export."
        }
    }

    private func writeTrack(for ride: RideSummary) {
        guard let data = try? Data(contentsOf: rideStore.trackURL(for: ride)) else { return }
        var lines = ["time,lat,lon,altitude"]
        for p in TrackEncoder.decodeV5Full(data) {
            lines.append("\(p.timestamp),\(p.lat),\(p.lon),\(p.altitude)")
        }
        try? lines.joined(separator: "\n").write(
            to: Self.folder.appendingPathComponent("\(ride.id.uuidString).track.csv"),
            atomically: true, encoding: .utf8)
    }

    private func writeSummary() {
        var lines = ["rideID,name,date,distance,appGain,appLoss,selected,stravaActivity,stravaGain,stravaElevHigh,stravaElevLow,stravaDistance,stravaDevice"]
        for ride in sortedRides {
            guard let s = results[ride.id] else { continue }
            let fields: [String] = [
                ride.id.uuidString, csvQuoted(ride.name), "\(ride.date.timeIntervalSince1970)",
                "\(ride.distance)", "\(ride.elevationGain)", "\(ride.elevationLoss)",
                selected.contains(ride.id) ? "1" : "0",
                s.activityID, "\(s.gain)", s.elevHigh.map { "\($0)" } ?? "", s.elevLow.map { "\($0)" } ?? "",
                "\(s.distance)", csvQuoted(s.deviceName ?? ""),
            ]
            lines.append(fields.joined(separator: ","))
        }
        try? lines.joined(separator: "\n").write(
            to: Self.folder.appendingPathComponent("summary.csv"), atomically: true, encoding: .utf8)
    }

    private func csvQuoted(_ s: String) -> String {
        guard s.contains(where: { $0 == "," || $0 == "\"" || $0 == "\n" }) else { return s }
        return "\"" + s.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    private func zipFolder() -> URL? {
        let fm = FileManager.default
        let dest = fm.temporaryDirectory.appendingPathComponent("Elevation-\(Int(Date().timeIntervalSince1970)).zip")
        try? fm.removeItem(at: dest)
        var copied = false
        var coordError: NSError?
        NSFileCoordinator().coordinate(readingItemAt: Self.folder, options: [.forUploading], error: &coordError) { zipURL in
            copied = (try? fm.copyItem(at: zipURL, to: dest)) != nil
        }
        return copied && coordError == nil ? dest : nil
    }

    // MARK: - Cache

    private func loadCache() {
        guard results.isEmpty,
              let data = try? Data(contentsOf: Self.cacheURL),
              let cached = try? JSONDecoder().decode([UUID: StravaResult].self, from: data) else { return }
        results = cached
    }

    private func saveCache() {
        try? FileManager.default.createDirectory(at: Self.folder, withIntermediateDirectories: true)
        guard let data = try? JSONEncoder().encode(results) else { return }
        try? data.write(to: Self.cacheURL, options: .atomic)
    }
}
#endif
