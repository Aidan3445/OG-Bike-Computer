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
            DiagnosticsLog.event("Route", "watch reports \(ids.count) routes")
        }
        if let size = context["watchStorageSize"] as? Int64 {
            watchStorageSize = size
        }
    }
}

#if os(iOS)
extension Notification.Name {
    /// Posted after queued file transfers to the watch are cancelled.
    static let watchTransferQueueChanged = Notification.Name("watchTransferQueueChanged")
}

extension ConnectivityManager {

    /// Routes with a file transfer still waiting to go to the watch.
    var queuedRouteTransferIDs: Set<UUID> {
        guard WCSession.default.activationState == .activated else { return [] }
        return Set(WCSession.default.outstandingFileTransfers.compactMap {
            Self.routeID(of: $0).flatMap(UUID.init(uuidString:))
        })
    }

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
            DiagnosticsLog.event("Route", "send \(route.id) refused, session state=\(WCSession.default.activationState.rawValue)")
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

        let session = WCSession.default
        DiagnosticsLog.event("Route", "before send \(route.id): \(outstandingTransferSummary())")
        // A resend replaces any earlier send of this route still waiting in
        // the queue, so stuck copies can't pile up behind each other.
        for transfer in session.outstandingFileTransfers where Self.routeID(of: transfer) == route.id.uuidString {
            transfer.cancel()
        }
        pruneStagedRoutes()

        // One file per send. Reusing a path let a resend overwrite a file an
        // older transfer was still reading, and its cleanup delete the new one.
        let stagedURL = Self.pendingRouteTransfersDirectory
            .appendingPathComponent("\(route.id.uuidString)_\(UUID().uuidString).json")

        do {
            try data.write(to: stagedURL, options: .atomic)
            var metadata: [String: Any] = ["type": "route"]
            if let action = pendingAction    { metadata["pendingAction"] = action }
            if let activity = activityType   { metadata["activityType"] = activity }
            metadata["stagedURL"] = stagedURL.lastPathComponent
            metadata["routeID"] = route.id.uuidString
            metadata["queuedAt"] = Date().timeIntervalSince1970
            session.transferFile(stagedURL, metadata: metadata)
            DiagnosticsLog.event("Route", "queued \(route.id) bytes=\(data.count) "
                + "action=\(pendingAction ?? "none") reachable=\(session.isReachable) "
                + "installed=\(session.isWatchAppInstalled) outstanding=\(session.outstandingFileTransfers.count)")
            scheduleStallCheck(routeID: route.id.uuidString)
        } catch {
            DiagnosticsLog.event("Route", "stage \(route.id) failed: \(error.localizedDescription)")
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

    /// Deletes a staged route file once its transfer is done. WatchConnectivity
    /// never retries a finished transfer, failed or cancelled ones included,
    /// so the file has no further use.
    func cleanUpStagedRoute(_ fileTransfer: WCSessionFileTransfer, error: Error?) {
        guard fileTransfer.file.metadata?["type"] as? String == "route" else { return }
        let routeID = Self.routeID(of: fileTransfer) ?? "unknown"
        if let error = error {
            DiagnosticsLog.event("Route", "transfer \(routeID) failed: \(error.localizedDescription)")
        } else {
            DiagnosticsLog.event("Route", "transfer \(routeID) delivered")
            DispatchQueue.main.async { self.stallWarningShown = false }
        }
        if let name = fileTransfer.file.metadata?["stagedURL"] as? String {
            try? FileManager.default.removeItem(at: Self.pendingRouteTransfersDirectory.appendingPathComponent(name))
        }
    }

    private static let stallCheckDelay: TimeInterval = 60

    /// Phone to watch file transfers can get stuck at 0% until both devices
    /// restart, while messages keep working. A transfer that hasn't started
    /// a minute later with the watch app open is that, not the watch being
    /// away, so the rider gets told how to clear it.
    private func scheduleStallCheck(routeID: String) {
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.stallCheckDelay) {
            let session = WCSession.default
            guard session.activationState == .activated, session.isReachable,
                  let transfer = session.outstandingFileTransfers.first(where: { Self.routeID(of: $0) == routeID }),
                  transfer.progress.fractionCompleted == 0 else { return }
            DiagnosticsLog.event("Route", "stalled \(routeID) after \(Int(Self.stallCheckDelay))s while reachable: "
                + self.outstandingTransferSummary())
            guard !self.stallWarningShown else { return }
            self.stallWarningShown = true
            self.routeTransferStalled = true
        }
    }

    /// Route ID for a queued route transfer. Sends from older builds only
    /// carry the staged file name, which starts with the ID.
    private static func routeID(of transfer: WCSessionFileTransfer) -> String? {
        let metadata = transfer.file.metadata
        guard metadata?["type"] as? String == "route" else { return nil }
        if let id = metadata?["routeID"] as? String { return id }
        return (metadata?["stagedURL"] as? String).map { String($0.prefix(36)) }
    }

    /// Removes staged files no queued transfer points at anymore, like ones
    /// left behind by failed sends from older builds.
    private func pruneStagedRoutes() {
        let dir = Self.pendingRouteTransfersDirectory
        let inUse = Set(WCSession.default.outstandingFileTransfers.compactMap {
            $0.file.metadata?["stagedURL"] as? String
        })
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        for name in files where !inUse.contains(name) {
            try? FileManager.default.removeItem(at: dir.appendingPathComponent(name))
        }
    }

    #if DEBUG
    /// Diagnostics escape hatch: cancels every file still waiting to go to
    /// the watch. Logs the queue before, and again once the cancels settle.
    func clearOutgoingFileTransfers() {
        let session = WCSession.default
        DiagnosticsLog.event("Route", "clearing queue: \(outstandingTransferSummary()) "
            + "userInfo=\(session.outstandingUserInfoTransfers.count) paired=\(session.isPaired) "
            + "installed=\(session.isWatchAppInstalled) reachable=\(session.isReachable)")
        session.outstandingFileTransfers.forEach { $0.cancel() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            self.pruneStagedRoutes()
            DiagnosticsLog.event("Route", "after clear: \(self.outstandingTransferSummary())")
            NotificationCenter.default.post(name: .watchTransferQueueChanged, object: nil)
        }
    }
    #endif

    /// One line describing everything waiting in the outgoing file queue.
    func outstandingTransferSummary() -> String {
        let transfers = WCSession.default.outstandingFileTransfers
        guard !transfers.isEmpty else { return "queue empty" }
        let now = Date().timeIntervalSince1970
        let items = transfers.map { t -> String in
            let type = t.file.metadata?["type"] as? String ?? "?"
            let id = Self.routeID(of: t).map { String($0.prefix(8)) } ?? "-"
            let age = (t.file.metadata?["queuedAt"] as? Double).map { "\(Int(now - $0))s" } ?? "?"
            return "\(type):\(id) transferring=\(t.isTransferring) progress=\(String(format: "%.2f", t.progress.fractionCompleted)) age=\(age)"
        }
        return "\(transfers.count) queued [\(items.joined(separator: "; "))]"
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    /// Saves a route sent from the phone, then runs any action bundled with
    /// it. Bundling guarantees the action never runs before the route exists.
    /// The file is deleted when the delegate call returns, so it's read right away.
    func receiveRouteFile(_ file: WCSessionFile) {
        guard let data = try? Data(contentsOf: file.fileURL) else {
            DiagnosticsLog.event("Route", "received file unreadable, metadata=\(file.metadata ?? [:])")
            return
        }
        let route: Route
        do {
            route = try JSONDecoder().decode(Route.self, from: data)
        } catch {
            DiagnosticsLog.event("Route", "received \(data.count) bytes, decode failed: \(error)")
            return
        }
        DiagnosticsLog.event("Route", "received \(route.id) bytes=\(data.count) "
            + "action=\(file.metadata?["pendingAction"] as? String ?? "none") store=\(routeStore != nil)")

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
        do {
            try WCSession.default.updateApplicationContext([
                "watchRouteIDs": ids,
                "watchStorageSize": totalSize
            ])
            DiagnosticsLog.event("Route", "reported \(ids.count) routes to phone")
        } catch {
            DiagnosticsLog.event("Route", "report of \(ids.count) routes failed: \(error.localizedDescription)")
        }
    }
}
#endif
#endif
