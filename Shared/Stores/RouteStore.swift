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
    }

    func delete(_ route: Route) {
        let fileURL = directory.appendingPathComponent("\(route.id.uuidString).json")
        try? FileManager.default.removeItem(at: fileURL)
        routes.removeAll { $0.id == route.id }
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

        let oldURL = directory.appendingPathComponent("\(route.id.uuidString).json")
        try? FileManager.default.removeItem(at: oldURL)

        let updated = Route(id: route.id, name: newName, points: route.points)

        if let data = try? JSONEncoder().encode(updated) {
            try? data.write(to: oldURL)
        }

        routes[index] = updated
        onChange?()
    }
}
