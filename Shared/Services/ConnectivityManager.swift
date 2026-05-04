//
//  Connectivity.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import Combine

final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    @Published var isReachable = false
    @Published var activationState: WCSessionActivationState = .notActivated
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var routeNamesOnWatch: Set<String> = []
    @Published var watchStorageSize: Int64 = 0
    @Published var lastEvent: String = "none"

    var onRouteReceived: ((Route) -> Void)?
    var onMetricConfigReceived: ((Data) -> Void)?
    var onUserSettingsReceived: ((Data) -> Void)?
    #if os(iOS)
    var onRideReceived: ((RideSummary) -> Void)?
    #endif

    #if os(watchOS)
    @Published var routeStore: RouteStore?
    @Published var rideStore: RideStore?
    #endif

    #if os(iOS)
    @Published var rideStore: RideStore?
    #endif

    private override init() {
        super.init()
    }

    func activate() {
        #if os(iOS)
        print("Activating WCSession on iOS")
        #elseif os(watchOS)
        print("Activating WCSession on watchOS")
        #endif

        guard WCSession.isSupported() else { return }
        WCSession.default.delegate = self
        WCSession.default.activate()
    }

    func attachStores(routeStore: RouteStore? = nil, rideStore: RideStore? = nil) {
        #if os(watchOS)
        if let rs = routeStore {
            self.routeStore = rs
            reportRoutes(rs.routes)
        }
        if let rs = rideStore {
            self.rideStore = rs
        }
        #endif

        #if os(iOS)
        if let rs = rideStore {
            self.rideStore = rs
        }
        #endif

        processOutstandingTransfers()
    }

    var canSendRoutes: Result<Void, ConnectivityError> {
        guard WCSession.isSupported() else {
            return .failure(.notSupported)
        }

        let session = WCSession.default

        #if os(iOS)
        guard session.isPaired else {
            return .failure(.notPaired)
        }

        guard session.isWatchAppInstalled else {
            return .failure(.watchAppNotInstalled)
        }
        #endif

        return .success(())
    }

    // Shared rides directory — usable even without RideStore attached
    static var ridesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("rides", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Callback when a ride start command is received from the phone (watchOS only).
    var onStartRideRequested: ((UUID?, ActivityType) -> Void)?

    /// Callback when a route change command is received from the phone (watchOS only).
    var onChangeRouteRequested: ((UUID?) -> Void)?

    /// Callback when a discard ride command is received from the phone (watchOS only).
    var onDiscardRideRequested: (() -> Void)?

    /// Callback when a voice toggle command is received from the phone (watchOS only).
    var onToggleVoiceRequested: (() -> Void)?

    /// Callback when the phone requests to hold the current ride (watchOS only).
    var onHoldRideRequested: (() -> Void)?

    /// Callback when the phone requests to continue a held ride (watchOS only).
    var onContinueHeldRideRequested: ((UUID) -> Void)?

    /// Callback when the phone requests to finalize a held ride (watchOS only).
    var onFinalizeHeldRideRequested: ((UUID) -> Void)?
}

// --- iOS ---

#if os(iOS)
extension ConnectivityManager {

    func requestWatchSync() {
        guard WCSession.default.activationState == .activated else { return }
        let ctx = WCSession.default.receivedApplicationContext

        DispatchQueue.main.async {
            if let names = ctx["watchRouteNames"] as? [String] {
                self.routeNamesOnWatch = Set(names)
            }
            if let size = ctx["watchStorageSize"] as? Int64 {
                self.watchStorageSize = size
            }
        }
    }

    /// Send a route file to the watch.
    ///
    /// - Parameters:
    ///   - route: The route to transfer.
    ///   - pendingAction: Optional action the watch should execute immediately
    ///     after saving the route. Supported values:
    ///     - `"changeRoute"` — switch to this route mid-ride
    ///     - `"startRide"`  — start a new ride with this route
    ///   - activityType: Activity type string used when `pendingAction == "startRide"`.
    ///     Defaults to `"cycling"` if omitted.
    ///   - completion: Called on the calling queue after the transfer is queued.
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

        guard let data = try? JSONEncoder().encode(route) else {
            completion(.failure(ConnectivityError.encodingFailed))
            return
        }

        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(route.id.uuidString).json")

        do {
            try data.write(to: tempURL)
            var metadata: [String: Any] = ["type": "route"]
            if let action = pendingAction    { metadata["pendingAction"] = action }
            if let activity = activityType   { metadata["activityType"] = activity }
            WCSession.default.transferFile(tempURL, metadata: metadata)
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

    func sendMetricConfig(_ data: Data) {
        guard WCSession.default.activationState == .activated else { return }

        // Try immediate delivery first (works even during a ride)
        if WCSession.default.isReachable {
            let base64 = data.base64EncodedString()
            WCSession.default.sendMessage(
                ["type": "metricConfig", "data": base64],
                replyHandler: { _ in print("[MetricConfig] Sent via message") },
                errorHandler: { error in
                    print("[MetricConfig] Message failed, falling back to userInfo: \(error)")
                    WCSession.default.transferUserInfo(["type": "metricConfig", "data": base64])
                }
            )
        } else {
            let base64 = data.base64EncodedString()
            WCSession.default.transferUserInfo(["type": "metricConfig", "data": base64])
            print("[MetricConfig] Queued via userInfo")
        }
    }

    func sendUserSettings(_ data: Data) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            let base64 = data.base64EncodedString()
            WCSession.default.sendMessage(
                ["type": "userSettings", "data": base64],
                replyHandler: { _ in print("[UserSettings] Sent via message") },
                errorHandler: { error in
                    print("[UserSettings] Message failed, falling back to userInfo: \(error)")
                    WCSession.default.transferUserInfo(["type": "userSettings", "data": base64])
                }
            )
        } else {
            let base64 = data.base64EncodedString()
            WCSession.default.transferUserInfo(["type": "userSettings", "data": base64])
            print("[UserSettings] Queued via userInfo")
        }
    }

    /// Tell the watch to delete all its routes.
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

    // MARK: - Ride Commands (iOS → Watch)
    /// Send a ride control command to the watch (startRide, changeRoute, toggleVoice).
    func sendRideCommand(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { reply in
                print("[RideCommand] Sent: \(message["type"] ?? "?"), reply: \(reply)")
            }, errorHandler: { error in
                print("[RideCommand] Failed: \(error). Queuing via userInfo.")
                WCSession.default.transferUserInfo(message)
            })
        } else {
            WCSession.default.transferUserInfo(message)
            print("[RideCommand] Watch not reachable, queued via userInfo")
        }
    }
    
    func sendHoldRide() {
        sendRideCommand(["type": "holdRide"])
    }

    func sendContinueHeldRide(rideID: UUID) {
        sendRideCommand(["type": "continueHeldRide", "rideID": rideID.uuidString])
    }

    func sendFinalizeHeldRide(rideID: UUID) {
        sendRideCommand(["type": "finalizeHeldRide", "rideID": rideID.uuidString])
    }

    /// Send acknowledgment to watch that a ride was successfully received.
    func sendRideAck(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }

        let msg: [String: Any] = ["type": "rideAck", "rideID": rideID.uuidString]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in
                print("[Transfer] Ack sent via message for \(rideID)")
            }, errorHandler: { error in
                print("[Transfer] Ack message failed, using userInfo: \(error)")
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            print("[Transfer] Ack queued via userInfo for \(rideID)")
        }
    }
}
#endif

// --- watchOS ---

#if os(watchOS)
extension ConnectivityManager {

    func sendRide(summary: RideSummary, trackURL: URL) {
        // Save locally on watch first
        saveRideLocally(summary: summary, trackURL: trackURL)

        // Record in transfer ledger as pending
        TransferLedger.shared.recordTransfer(rideID: summary.id)

        guard WCSession.default.activationState == .activated else {
            print("Cannot send ride: WCSession not activated (saved locally, will retry)")
            return
        }

        transferRideToPhone(summary: summary)
    }

    /// Transfer a ride's track file to the phone. The track must already exist in the local rides directory.
    private func transferRideToPhone(summary: RideSummary) {
        let trackURL = Self.ridesDirectory.appendingPathComponent(summary.trackFilename)
        guard FileManager.default.fileExists(atPath: trackURL.path) else {
            print("[Transfer] Track file missing for \(summary.name), cannot transfer")
            return
        }

        WCSession.default.transferFile(
            trackURL,
            metadata: [
                "type": "rideTrack",
                "summaryJSON": (try? JSONEncoder().encode(summary))
                    .flatMap { String(data: $0, encoding: .utf8) } ?? ""
            ]
        )

        print("Queued ride transfer: \(summary.name)")
    }

    private func saveRideLocally(summary: RideSummary, trackURL: URL) {
        let dir = Self.ridesDirectory

        // Copy track file — always overwrite so second/third holds accumulate correctly
        let destTrack = dir.appendingPathComponent(summary.trackFilename)
        try? FileManager.default.removeItem(at: destTrack)
        try? FileManager.default.copyItem(at: trackURL, to: destTrack)

        // Save summary JSON
        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL)
        }

        // Update in-memory store if attached
        DispatchQueue.main.async {
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
        }

        print("Ride saved locally on watch: \(summary.name)")
    }

    /// Retry transferring any unconfirmed rides to the phone.
    func retryPendingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        let pending = TransferLedger.shared.pendingRideIDs()
        guard !pending.isEmpty else { return }

        print("[Transfer] Retrying \(pending.count) unconfirmed ride(s)")

        let dir = Self.ridesDirectory
        for rideID in pending {
            let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
            guard let data = try? Data(contentsOf: summaryURL),
                  let summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
                print("[Transfer] Cannot load summary for \(rideID), removing from ledger")
                TransferLedger.shared.remove(rideID: rideID)
                continue
            }
            transferRideToPhone(summary: summary)
        }
    }

    /// Handle a transfer acknowledgment from the phone.
    func handleTransferAck(rideID: UUID) {
        TransferLedger.shared.markConfirmed(rideID: rideID)
        print("[Transfer] Confirmed: \(rideID)")
    }

    /// Clean up old confirmed rides (7 days) and expired unconfirmed rides (30 days).
    func cleanupOldRides() {
        let dir = Self.ridesDirectory
        let fm = FileManager.default

        // Clean confirmed rides older than 7 days
        let confirmedToRemove = TransferLedger.shared.confirmedRideIDsOlderThan(days: 7)
        for rideID in confirmedToRemove {
            deleteLocalRide(rideID: rideID, dir: dir, fm: fm)
            TransferLedger.shared.remove(rideID: rideID)
            print("[Transfer] Cleaned up confirmed ride: \(rideID)")
        }

        // Clean unconfirmed rides older than 30 days (data likely lost, can't keep forever)
        let expiredToRemove = TransferLedger.shared.pendingRideIDsOlderThan(days: 30)
        for rideID in expiredToRemove {
            deleteLocalRide(rideID: rideID, dir: dir, fm: fm)
            TransferLedger.shared.remove(rideID: rideID)
            print("[Transfer] Expired unconfirmed ride: \(rideID)")
        }
    }

    private func deleteLocalRide(rideID: UUID, dir: URL, fm: FileManager) {
        let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")

        // Read summary to get track filename before deleting
        if let data = try? Data(contentsOf: summaryURL),
           let summary = try? JSONDecoder().decode(RideSummary.self, from: data) {
            let trackURL = dir.appendingPathComponent(summary.trackFilename)
            try? fm.removeItem(at: trackURL)
        }
        try? fm.removeItem(at: summaryURL)

        // Remove from in-memory store
        DispatchQueue.main.async {
            self.rideStore?.rides.removeAll { $0.id == rideID }
        }
    }

    func reportRoutes(_ routes: [Route]) {
        guard WCSession.default.activationState == .activated else { return }
        let names = routes.map { $0.name }
        let totalSize = routes.reduce(0) { $0 + ($1.points.count * 32) } // ~32 bytes per coordinate
        try? WCSession.default.updateApplicationContext([
            "watchRouteNames": names,
            "watchStorageSize": totalSize
        ])
    }
}
#endif

// --- WCSessionDelegate ---

extension ConnectivityManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isReachable = session.isReachable

            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.requestWatchSync()
            #endif
        }

        if activationState == .activated, session.hasContentPending {
            print("WCSession has content pending delivery")
        }

        #if os(watchOS)
        if activationState == .activated {
            retryPendingTransfers()
            cleanupOldRides()
        }
        #endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }

        #if os(watchOS)
        // When phone becomes reachable, retry any pending transfers and clean up old rides
        if session.isReachable {
            retryPendingTransfers()
            cleanupOldRides()
        }
        #endif
    }

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        let fileType = file.metadata?["type"] as? String

        #if os(iOS)
        if fileType == "rideTrack" {
            handleRideTransfer(file)
            return
        }
        #endif

        guard let data = try? Data(contentsOf: file.fileURL),
              let route = try? JSONDecoder().decode(Route.self, from: data) else {
            print("Failed to decode transferred file")
            return
        }

        #if os(watchOS)
        let pendingAction  = file.metadata?["pendingAction"] as? String
        let activityString = file.metadata?["activityType"]  as? String

        DispatchQueue.main.async {
            if let existing = self.routeStore?.routes.first(where: { $0.name == route.name }) {
                self.routeStore?.delete(existing)
            }
            self.routeStore?.save(route)
            self.routeStore.map { self.reportRoutes($0.routes) }

            // Execute any action that was bundled with the file transfer so
            // the command is guaranteed to arrive *after* the route is saved.
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
        #endif
    }

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            if let names = applicationContext["watchRouteNames"] as? [String] {
                self.routeNamesOnWatch = Set(names)
            }
            if let size = applicationContext["watchStorageSize"] as? Int64 {
                self.watchStorageSize = size
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        DispatchQueue.main.async {
            self.lastEvent = "got userInfo: \(userInfo.keys)"
        }

        if let type = userInfo["type"] as? String,
           type == "metricConfig",
           let base64 = userInfo["data"] as? String,
           let data = Data(base64Encoded: base64) {
            DispatchQueue.main.async {
                self.onMetricConfigReceived?(data)
            }
            return
        }

        if let type = userInfo["type"] as? String,
           type == "userSettings",
           let base64 = userInfo["data"] as? String,
           let data = Data(base64Encoded: base64) {
            DispatchQueue.main.async {
                self.onUserSettingsReceived?(data)
            }
            return
        }

        #if os(watchOS)
        if let type = userInfo["type"] as? String,
           type == "rideAck",
           let idString = userInfo["rideID"] as? String,
           let rideID = UUID(uuidString: idString) {
            handleTransferAck(rideID: rideID)
            return
        }

        if let type = userInfo["type"] as? String,
           type == "clearAllRoutes" {
            DispatchQueue.main.async {
                self.routeStore?.deleteAll()
                self.routeStore.map { self.reportRoutes($0.routes) }
            }
            return
        }

        // Ride commands queued via transferUserInfo when watch wasn't reachable
        if let type = userInfo["type"] as? String {
            switch type {
            case "holdRide":
                DispatchQueue.main.async { self.onHoldRideRequested?() }
            case "continueHeldRide":
                if let idStr = userInfo["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    DispatchQueue.main.async { self.onContinueHeldRideRequested?(rideID) }
                }
            case "finalizeHeldRide":
                if let idStr = userInfo["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    DispatchQueue.main.async { self.onFinalizeHeldRideRequested?(rideID) }
                }
            default:
                break
            }
        }
        #endif

        if let data = userInfo["route"] as? Data,
           let route = try? JSONDecoder().decode(Route.self, from: data) {
            DispatchQueue.main.async {
                self.onRouteReceived?(route)
            }
        }
    }

    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message["wake"] != nil {
            print("Woken by phone")
            replyHandler(["awake": true])
            return
        }

        // Handle metric config on both platforms
        if let type = message["type"] as? String,
           type == "metricConfig",
           let base64 = message["data"] as? String,
           let data = Data(base64Encoded: base64) {
            DispatchQueue.main.async {
                self.onMetricConfigReceived?(data)
            }
            replyHandler(["received": true])
            return
        }

        // Handle user settings on both platforms
        if let type = message["type"] as? String,
           type == "userSettings",
           let base64 = message["data"] as? String,
           let data = Data(base64Encoded: base64) {
            DispatchQueue.main.async {
                self.onUserSettingsReceived?(data)
            }
            replyHandler(["received": true])
            return
        }

        // Handle ride transfer acknowledgment on watch
        #if os(watchOS)
        if let type = message["type"] as? String,
           type == "rideAck",
           let idString = message["rideID"] as? String,
           let rideID = UUID(uuidString: idString) {
            handleTransferAck(rideID: rideID)
            replyHandler(["received": true])
            return
        }

        if let type = message["type"] as? String,
           type == "clearAllRoutes" {
            DispatchQueue.main.async {
                self.routeStore?.deleteAll()
                self.routeStore.map { self.reportRoutes($0.routes) }
            }
            replyHandler(["cleared": true])
            return
        }

        // Ride commands from phone
        if let type = message["type"] as? String {
            switch type {
            case "startRide":
                let routeIDStr = message["routeID"] as? String
                let routeID = routeIDStr.flatMap { UUID(uuidString: $0) }
                let activityStr = message["activity"] as? String ?? "cycling"
                let activity = ActivityType(rawValue: activityStr) ?? .cycling
                DispatchQueue.main.async {
                    self.onStartRideRequested?(routeID, activity)
                }
                replyHandler(["started": true])
                return
            case "changeRoute":
                let routeID = (message["routeID"] as? String).flatMap { UUID(uuidString: $0) }
                DispatchQueue.main.async {
                    self.onChangeRouteRequested?(routeID)
                }
                replyHandler(["changed": true])
                return
            case "toggleVoice":
                DispatchQueue.main.async {
                    self.onToggleVoiceRequested?()
                }
                replyHandler(["toggled": true])
                return
            case "discardRide":
                DispatchQueue.main.async {
                    self.onDiscardRideRequested?()
                }
                replyHandler(["discarded": true])
                return
            case "holdRide":
                DispatchQueue.main.async {
                    self.onHoldRideRequested?()
                }
                replyHandler(["held": true])
                return
            case "continueHeldRide":
                if let idStr = message["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    DispatchQueue.main.async {
                        self.onContinueHeldRideRequested?(rideID)
                    }
                }
                replyHandler(["continuing": true])
                return
            case "finalizeHeldRide":
                if let idStr = message["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    DispatchQueue.main.async {
                        self.onFinalizeHeldRideRequested?(rideID)
                    }
                }
                replyHandler(["finalized": true])
                return
            default:
                break
            }
        }
        #endif

        #if os(iOS) && !WIDGET_EXTENSION
        print("Received message: \(message.keys), \(message["type"] as? String ?? "no type")")
        if let type = message["type"] as? String,
           type == "speech",
           let text = message["text"] as? String {
            PhoneSpeechPlayer.shared.speak(text)
            replyHandler(["spoken": true])
            return
        }
        #endif

        replyHandler([:])
    }

    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}

private extension ConnectivityManager {

    func processOutstandingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        #if os(iOS)
        let outstanding = WCSession.default.outstandingFileTransfers
        print("Outstanding file transfers: \(outstanding.count)")
        #endif
    }

    #if os(iOS)
    func handleRideTransfer(_ file: WCSessionFile) {
        guard let summaryString = file.metadata?["summaryJSON"] as? String,
              let summaryData = summaryString.data(using: .utf8),
              var summary = try? JSONDecoder().decode(RideSummary.self, from: summaryData) else {
            print("Failed to decode ride summary")
            return
        }

        let dir = Self.ridesDirectory
        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")

        // Check if this ride already exists on disk (e.g. from a previous transfer)
        // If so, preserve any upload records that were added after the first transfer
        let isRetransmit: Bool
        if let existingData = try? Data(contentsOf: summaryURL),
           let existingSummary = try? JSONDecoder().decode(RideSummary.self, from: existingData) {
            isRetransmit = true
            // Preserve upload records from the existing version — the watch
            // doesn't know about uploads, so its summary always has uploads: nil
            if let existingUploads = existingSummary.uploads, !existingUploads.isEmpty {
                summary.uploads = existingUploads
            }
        } else {
            isRetransmit = false
        }

        // Save track file
        let destURL = dir.appendingPathComponent(summary.trackFilename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)
        } catch {
            print("Failed to copy track file: \(error)")
            return
        }

        // Save summary (with preserved upload records if retransmit)
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL, options: .atomic)
        }

        // If rideStore is attached, update in-memory immediately
        DispatchQueue.main.async {
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary  // update existing (e.g. held → completed)
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
            print("Ride received: \(summary.name)\(isRetransmit ? " (retransmit)" : "")")

            // Only trigger auto-upload for new rides, not retransmits
            if !isRetransmit {
                self.onRideReceived?(summary)
            }
        }

        // Send acknowledgment back to watch so it can mark the ride as confirmed
        sendRideAck(rideID: summary.id)
    }
    #endif
}
#endif // canImport(WatchConnectivity)
