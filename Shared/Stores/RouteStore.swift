//
//  RouteStore.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import Combine

class RouteStore: ObservableObject {
    @Published var routes: [Route] = []

    var onImport: ((Route) -> Void)?
    var onChange: (() -> Void)?
    private let directory: URL

    init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        directory = docs.appendingPathComponent("routes", isDirectory: true)

        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        loadAll()
    }

    func save(_ route: Route) {
        let fileURL = directory.appendingPathComponent("\(route.id.uuidString).json")
        if let data = try? JSONEncoder().encode(route) {
            try? data.write(to: fileURL)
        }
        if !routes.contains(where: { $0.id == route.id }) {
            routes.append(route)
        }
        onChange?()
        onImport?(route)
    }

    func delete(_ route: Route) {
        let fileURL = directory.appendingPathComponent("\(route.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        routes.removeAll { $0.id == route.id }
        onChange?()
    }

    func deleteAll() {
        let fm = FileManager.default
        if let files = try? fm.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil) {
            for file in files {
                try? fm.removeItem(at: file)
            }
        }
        routes.removeAll()
        onChange?()
    }

    func loadAll() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: nil) else { return }

        routes = files
            .filter { $0.pathExtension == "json" }
            .compactMap { url in
                guard let data = try? Data(contentsOf: url) else { return nil }
                return try? JSONDecoder().decode(Route.self, from: data)
            }
            .sorted { $0.name < $1.name }
    }
    
    var storageSize: Int64 {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: [.fileSizeKey]) else { return 0 }

        return files.reduce(0) { total, url in
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            return total + Int64(size)
        }
    }

    func rename(_ route: Route, to newName: String) {
        guard let index = routes.firstIndex(where: { $0.id == route.id }) else { return }
        var updated = route
        updated.name = newName
        let fileURL = directory.appendingPathComponent("\(route.id.uuidString).json")
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: fileURL)
        }
        routes[index] = updated
        onChange?()
    }

    /// Persist Cue Editor decisions back to the stored Route. Returns the updated
    /// Route so callers (and the watch sync layer) can pick it up.
    /// If the route is currently on the watch, also queues an automatic
    /// resync so the watch's stored copy stays in lock-step with the edits.
    @discardableResult
    func updateCueEdits(routeID: UUID, edits: CueEdits?) -> Route? {
        guard let index = routes.firstIndex(where: { $0.id == routeID }) else { return nil }
        var updated = routes[index]
        // Treat an empty edits structure as nil so unedited routes stay clean.
        updated.cueEdits = (edits?.isEmpty == true) ? nil : edits
        let fileURL = directory.appendingPathComponent("\(routeID.uuidString).json")
        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: fileURL)
        }
        routes[index] = updated
        onChange?()
        autoResyncIfOnWatch(updated)
        return updated
    }

    /// If a route is already on the watch, replace it with the latest copy so
    /// edits propagate without the user having to tap "Send to Watch" again.
    /// The send is queued via WatchConnectivity; if the watch is unreachable
    /// the transfer will resume when it comes back online.
    private func autoResyncIfOnWatch(_ route: Route) {
        #if os(iOS)
        let cm = ConnectivityManager.shared
        guard cm.routeIDsOnWatch.contains(route.id) else { return }
        cm.sendRoute(route) { _ in }
        #endif
    }
}
