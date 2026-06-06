//
//  RouteImportPipeline.swift
//  OG Bike Computer
//
//  Single ingestion point for all GPX imports — Share Sheet, file picker, URL,
//  and AppIntents all funnel through here so parsing and saving logic live in
//  exactly one place.
//
//  Callers that want to show the interactive action sheet afterwards should
//  pass the returned routes to RouteImportCoordinator.shared.handle(_:).
//  AppIntents that know the destination up-front skip the coordinator entirely.
//

import Foundation
import Combine

// MARK: - Pipeline

final class RouteImportPipeline {
    static let shared = RouteImportPipeline()
    private init() {}

    /// Set once at app startup (OG_Bike_ComputerApp.onAppear).
    /// When nil the pipeline writes routes directly to disk so AppIntents
    /// can still save routes before the main app process is fully running.
    private(set) weak var routeStore: RouteStore?

    func configure(routeStore: RouteStore) {
        self.routeStore = routeStore
    }

    // MARK: Import

    /// Parse GPX `data`, persist every found route, and return them.
    ///
    /// Must be called on the **main thread** when `routeStore` is set,
    /// because `RouteStore.save` mutates a `@Published` property.
    /// AppIntents call this via `await MainActor.run { }`.
    @discardableResult
    func importGPX(data: Data) -> [Route] {
        let routes = GPXParser().parse(data: data)
        for route in routes {
            if let store = routeStore {
                store.save(route)          // in-app: updates @Published list
            } else {
                writeToDisk(route)         // intent / extension: disk only
            }
        }
        return routes
    }

    // MARK: Disk fallback (used by AppIntents before app is foregrounded)

    private func writeToDisk(_ route: Route) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir  = docs.appendingPathComponent("routes", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent("\(route.id.uuidString).json")
        if let data = try? JSONEncoder().encode(route) {
            try? data.write(to: file)
        }
    }
}

// MARK: - Coordinator

/// Holds routes that were just imported and need a user decision.
/// Present `RouteImportActionSheet` whenever `showActionSheet` is true.
final class RouteImportCoordinator: ObservableObject {
    static let shared = RouteImportCoordinator()
    private init() {}

    @Published var pendingRoutes: [Route] = []
    @Published var showActionSheet = false
    /// Route IDs that the auto-send setting has already shipped to the watch.
    /// The action sheet reads this on appear to pre-mark the row as "Sent to
    /// Watch" so the rider doesn't have to tap the same action twice.
    @Published var autoSentRouteIDs: Set<UUID> = []

    /// Read by `handle(_:)`. Mirrors the `autoSendRoutesToWatch` `@AppStorage`
    /// key in `RideSettingsView`. Settings UI writes the key directly; the
    /// coordinator reads it at import time.
    static let autoSendDefaultsKey = "autoSendRoutesToWatch"

    func handle(_ routes: [Route]) {
        guard !routes.isEmpty else { return }
        pendingRoutes = routes
        autoSentRouteIDs = []
        showActionSheet = true

        let autoSend = UserDefaults.standard.bool(forKey: Self.autoSendDefaultsKey)
        guard autoSend else { return }
        let conn = ConnectivityManager.shared
        guard conn.isPaired, conn.isWatchAppInstalled else { return }
        for route in routes {
            conn.sendRoute(route) { [weak self] result in
                DispatchQueue.main.async {
                    if case .success = result {
                        self?.autoSentRouteIDs.insert(route.id)
                    }
                }
            }
        }
    }

    /// Fire the auto-send-to-watch behavior for a single route without showing
    /// the action sheet. Used by service imports (Strava / RWGPS) where the
    /// user is already inside a picker UI and doesn't need the sheet — they
    /// just want the same "send-to-watch on import" honored as for GPX files.
    func autoSendIfEnabled(_ route: Route) {
        let autoSend = UserDefaults.standard.bool(forKey: Self.autoSendDefaultsKey)
        guard autoSend else { return }
        let conn = ConnectivityManager.shared
        guard conn.isPaired, conn.isWatchAppInstalled else { return }
        conn.sendRoute(route) { _ in }
    }

    func clear() {
        pendingRoutes = []
        autoSentRouteIDs = []
        showActionSheet = false
    }
}
