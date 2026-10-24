//
//  ConnectivityManager+Routes.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

extension ConnectivityManager {

    /// Reads the route list and storage size the watch publishes in its application context.
    func applyWatchContext(_ context: [String: Any]) {
        if let ids = context["watchRouteIDs"] as? [String] {
            routeIDsOnWatch = Set(ids.compactMap(UUID.init(uuidString:)))
        }
        if let size = context["watchStorageSize"] as? Int64 {
            watchStorageSize = size
        }
    }
}

#if os(iOS)
extension ConnectivityManager {

    func requestWatchSync() {
        guard WCSession.default.activationState == .activated else { return }
        let ctx = WCSession.default.receivedApplicationContext

        DispatchQueue.main.async {
            self.applyWatchContext(ctx)
        }
    }

    /// Queues a route file for the watch.
    ///
    /// - Parameters:
    ///   - pendingAction: Runs on the watch once the route is saved, either
    ///     `"changeRoute"` (switch to it mid ride) or `"startRide"`.
    ///   - activityType: Used with `"startRide"`. The watch assumes `"cycling"` if omitted.
    ///   - completion: Called once the transfer is queued, not when it lands.
    func sendRoute(
        _ route: Route,
        pendingAction: String? = nil,
        activityType: String? = nil,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            completion(.failure(ConnectivityError.notReachable))
            return
        }

        // Simplify here so the watch never walks the full point list to draw its elevation chart.
        var routeToSend = route
        if routeToSend.simplifiedElevation == nil {
            routeToSend.simplifiedElevation = RouteElevationSimplifier.simplify(routeToSend)
        }

        guard let data = try? JSONEncoder().encode(routeToSend) else {
            completion(.failure(ConnectivityError.encodingFailed))
            return
        }

        let stagedURL = Self.pendingRouteTransfersDirectory
            .appendingPathComponent("\(route.id.uuidString).json")

        do {
            try data.write(to: stagedURL, options: .atomic)
            var metadata: [String: Any] = ["type": "route"]
            if let action = pendingAction    { metadata["pendingAction"] = action }
            if let activity = activityType   { metadata["activityType"] = activity }
            metadata["stagedURL"] = stagedURL.lastPathComponent
            WCSession.default.transferFile(stagedURL, metadata: metadata)
            print("Queued file transfer: \(route.name) (\(data.count) bytes)"
                + (pendingAction.map { ", pendingAction=\($0)" } ?? ""))
        } catch {
            completion(.failure(error))
            return
        }

        WCSession.default.sendMessage(
            ["wake": true],
            replyHandler: { _ in },
            errorHandler: { _ in }
        )

        completion(.success(()))
    }

    /// Tells the watch to delete all of its routes.
    func sendClearAllRoutes() {
        guard WCSession.default.activationState == .activated else { return }

        let msg: [String: Any] = ["type": "clearAllRoutes"]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in
                print("[ClearRoutes] Sent via message")
            }, errorHandler: { error in
                print("[ClearRoutes] Message failed, using userInfo: \(error)")
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            print("[ClearRoutes] Queued via userInfo")
        }
    }

    /// Deletes a staged route file once its transfer succeeds. On failure the
    /// file stays so WatchConnectivity can retry it.
    func cleanUpStagedRoute(_ fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let stagingDir = Self.pendingRouteTransfersDirectory.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(stagingDir) else { return }
        if let error = error {
            print("[Transfer] File transfer finished with error, leaving staged file in place: \(error)")
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    /// Saves a route sent from the phone, then runs any action bundled with
    /// it. Bundling guarantees the action never runs before the route exists.
    /// The file is deleted when the delegate call returns, so it's read right away.
    func receiveRouteFile(_ file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL),
              let route = try? JSONDecoder().decode(Route.self, from: data) else {
            print("Failed to decode transferred file")
            return
        }

        let pendingAction  = file.metadata?["pendingAction"] as? String
        let activityString = file.metadata?["activityType"]  as? String

        DispatchQueue.main.async {
            // Match on id so an updated route replaces the old copy while two
            // different routes with the same name both stay.
            if let existing = self.routeStore?.routes.first(where: { $0.id == route.id }) {
                self.routeStore?.delete(existing)
            }
            self.routeStore?.save(route)
            self.routeStore.map { self.reportRoutes($0.routes) }

            switch pendingAction {
            case "changeRoute":
                print("[WC] File received with pendingAction=changeRoute → \(route.name)")
                self.onChangeRouteRequested?(route.id)
            case "startRide":
                let activity = ActivityType(rawValue: activityString ?? "cycling") ?? .cycling
                print("[WC] File received with pendingAction=startRide → \(route.name)")
                self.onStartRideRequested?(route.id, activity)
            default:
                break
            }
        }
    }

    func clearAllRoutesFromPhone() {
        DispatchQueue.main.async {
            self.routeStore?.deleteAll()
            self.routeStore.map { self.reportRoutes($0.routes) }
        }
    }

    /// Publishes the route list and a rough storage size for the phone's library.
    func reportRoutes(_ routes: [Route]) {
        guard WCSession.default.activationState == .activated else { return }
        let ids = routes.map { $0.id.uuidString }
        let totalSize = routes.reduce(0) { $0 + ($1.points.count * 32) } // ~32 bytes per coordinate
        try? WCSession.default.updateApplicationContext([
            "watchRouteIDs": ids,
            "watchStorageSize": totalSize
        ])
    }
}
#endif
#endif
