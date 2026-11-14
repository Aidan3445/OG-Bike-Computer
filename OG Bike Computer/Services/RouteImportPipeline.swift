//
//  RouteImportPipeline.swift
//  OG Bike Computer
//
//  Single ingestion point for all GPX imports — Share Sheet, file picker, URL,
//  and AppIntents all funnel through here so parsing and saving logic live in
//  exactly one place.
//
//  Routes that match one already saved come back unsaved, flagged with the
//  match, so the caller can resolve them: the import sheet asks, the
//  Shortcuts action follows its "if it's a duplicate" option.
//

import Combine
import Foundation

// MARK: - Duplicates

/// An existing route that a newly imported one matches, strongest match first.
enum RouteDuplicate {
    /// Same route from the same service, likely an updated version of it.
    case sameSource(Route)
    /// Identical track, whatever it's called.
    case sameTrack(Route)
    /// Same name but a different track, likely a revision.
    case sameName(Route)

    var existing: Route {
        switch self {
        case .sameSource(let r), .sameTrack(let r), .sameName(let r): return r
        }
    }

    /// One line for the import sheet.
    var explanation: String {
        switch self {
        case .sameSource(let r):
            return
                "Already imported from \(r.source?.service.displayName ?? "this service") as \"\(r.name)\"."
        case .sameTrack(let r): return "Same track as \"\(r.name)\"."
        case .sameName: return "A different route already has this name."
        }
    }

    /// What Shortcuts' Automatic option and the import sheet's default do.
    var automaticChoice: RouteDuplicateChoice {
        switch self {
        case .sameSource: return .replace
        case .sameTrack: return .useExisting
        case .sameName: return .keepBoth
        }
    }
}

enum RouteDuplicateChoice: Hashable {
    case replace, keepBoth, useExisting
}

/// A parsed route that hasn't been saved yet, with any duplicate it matches.
struct RouteImportCandidate: Identifiable {
    let route: Route
    let duplicate: RouteDuplicate?
    var id: UUID { route.id }
}

// MARK: - Pipeline

final class RouteImportPipeline {
    static let shared = RouteImportPipeline()
    private init() {}

    /// Set once at app startup (OG_Bike_ComputerApp.onAppear). Before then,
    /// e.g. a Shortcut run early, a store is loaded from disk on demand.
    private(set) weak var routeStore: RouteStore?

    func configure(routeStore: RouteStore) {
        self.routeStore = routeStore
    }

    /// Main thread only: `RouteStore` publishes its list.
    private var store: RouteStore { routeStore ?? RouteStore() }

    // MARK: Import

    /// Parse GPX `data` and save every route that isn't a duplicate. Returns
    /// all of them, so duplicates can be resolved afterwards.
    ///
    /// Main thread only, since `RouteStore.save` publishes.
    func importGPX(data: Data) -> [RouteImportCandidate] {
        let store = store
        let candidates = GPXParser().parse(data: data).map { route in
            RouteImportCandidate(
                route: route, duplicate: Self.duplicate(of: route, in: store.routes))
        }
        for candidate in candidates where candidate.duplicate == nil {
            store.save(candidate.route)
        }
        return candidates
    }

    /// Saves, replaces or skips a duplicate and returns the route that ends
    /// up in the list. Main thread only.
    @discardableResult
    func resolve(_ candidate: RouteImportCandidate, as choice: RouteDuplicateChoice) -> Route {
        let store = store
        guard let duplicate = candidate.duplicate else {
            store.save(candidate.route)
            return candidate.route
        }
        switch choice {
        case .replace:
            return store.replace(duplicate.existing, with: candidate.route)
        case .keepBoth:
            var copy = candidate.route
            copy.name = Self.unusedName(for: copy.name, among: store.routes)
            store.save(copy)
            return copy
        case .useExisting:
            return duplicate.existing
        }
    }

    /// An already imported route from the same service with this remote ID.
    func existingRoute(service: IntegrationServiceID, remoteID: String) -> Route? {
        store.routes.first { $0.source?.service == service && $0.source?.remoteID == remoteID }
    }

    // MARK: Matching

    static func duplicate(of route: Route, in existing: [Route]) -> RouteDuplicate? {
        if let source = route.source,
            let match = existing.first(where: { $0.source == source })
        {
            return .sameSource(match)
        }
        let key = trackKey(route)
        if let match = existing.first(where: {
            $0.points.count == route.points.count && trackKey($0) == key
        }) {
            return .sameTrack(match)
        }
        let name = normalized(route.name)
        if let match = existing.first(where: { normalized($0.name) == name }) {
            return .sameName(match)
        }
        return nil
    }

    /// Coordinates rounded to about a meter, so a re-export of the same
    /// route matches even if the last digits wobble.
    private static func trackKey(_ route: Route) -> [Int64] {
        route.points.flatMap { [Int64(($0.lat * 1e5).rounded()), Int64(($0.lon * 1e5).rounded())] }
    }

    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    /// "Loop" becomes "Loop (2)", or the next number that isn't taken.
    private static func unusedName(for name: String, among routes: [Route]) -> String {
        let taken = Set(routes.map { normalized($0.name) })
        var n = 2
        while taken.contains(normalized("\(name) (\(n))")) { n += 1 }
        return "\(name) (\(n))"
    }
}

// MARK: - Coordinator

/// Holds routes that were just imported and need a user decision.
/// Present `RouteImportActionSheet` whenever `showActionSheet` is true.
final class RouteImportCoordinator: ObservableObject {
    static let shared = RouteImportCoordinator()
    private init() {}

    /// Duplicates stay flagged until the rider picks what to do with them.
    @Published var pending: [RouteImportCandidate] = []
    @Published var showActionSheet = false
    /// Route IDs that the auto-send setting has already shipped to the watch.
    /// The action sheet reads this on appear to pre-mark the row as "Sent to
    /// Watch" so the rider doesn't have to tap the same action twice.
    @Published var autoSentRouteIDs: Set<UUID> = []

    /// The toggles in Phone settings and the Routes tab Import menu write this
    /// key; `handle(_:)` reads it at import time.
    static let autoSendDefaultsKey = "autoSendRoutesToWatch"

    func handle(_ candidates: [RouteImportCandidate]) {
        guard !candidates.isEmpty else { return }
        pending = candidates
        autoSentRouteIDs = []
        showActionSheet = true
        for candidate in candidates where candidate.duplicate == nil {
            autoSend(candidate.route)
        }
    }

    /// Resolves a duplicate from the sheet and swaps in the resulting route.
    @discardableResult
    func resolve(_ candidate: RouteImportCandidate, as choice: RouteDuplicateChoice) -> Route {
        let route = RouteImportPipeline.shared.resolve(candidate, as: choice)
        if let index = pending.firstIndex(where: { $0.id == candidate.id }) {
            pending[index] = RouteImportCandidate(route: route, duplicate: nil)
        }
        // A replaced route already on the watch gets resent by the store.
        let onWatch = ConnectivityManager.shared.routeIDsOnWatch.contains(route.id)
        if choice == .keepBoth || (choice == .replace && !onWatch) {
            autoSend(route)
        }
        return route
    }

    /// Fire the auto-send-to-watch behavior for a single route without showing
    /// the action sheet. Used by service imports (Strava / RWGPS) where the
    /// user is already inside a picker UI and doesn't need the sheet — they
    /// just want the same "send-to-watch on import" honored as for GPX files.
    func autoSendIfEnabled(_ route: Route) {
        autoSend(route)
    }

    private func autoSend(_ route: Route) {
        let autoSend = UserDefaults.standard.bool(forKey: Self.autoSendDefaultsKey)
        guard autoSend else { return }
        let conn = ConnectivityManager.shared
        guard conn.isPaired, conn.isWatchAppInstalled else { return }
        conn.sendRoute(route) { [weak self] result in
            DispatchQueue.main.async {
                if case .success = result {
                    self?.autoSentRouteIDs.insert(route.id)
                }
            }
        }
    }

    func clear() {
        pending = []
        autoSentRouteIDs = []
        showActionSheet = false
    }
}
