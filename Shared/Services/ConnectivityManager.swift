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
    /// Phone-side hook: a voice alert just arrived from the watch. The
    /// receiver decides what to do with it (dedupe, expire-check, hand to
    /// speech synthesizer). See PhoneAlertReceiver.
    var onVoiceAlertReceived: ((AlertPayload) -> Void)?
    #endif
    #if os(watchOS)
    /// Watch-side hook: phone confirmed AVSpeechSynthesizer.didStart for an
    /// alert id. The transport uses this to cancel the matching fallback
    /// timer and let VoiceNavigator advance its queue.
    var onAlertAckReceived: ((UUID) -> Void)?
    #endif
    #if os(iOS)
    var onRideReceived: ((RideSummary) -> Void)?
    /// Ride IDs currently being transferred from the watch (file in flight).
    @Published var pendingTransferRideIDs: Set<UUID> = []
    /// True when the phone has detected the watch's ride session ended but the
    /// ride summary/file hasn't started transferring yet. Used to show an
    /// immediate "Waiting for ride from watch" placeholder in the ride list.
    @Published var isAwaitingIncomingRide: Bool = false
    private var awaitingIncomingRideTimeout: DispatchWorkItem?
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

    /// Persistent staging directory for route-file transfers to the watch.
    /// WatchConnectivity's outstanding-transfer queue survives app relaunches,
    /// but the source file must still exist on disk when the OS retries the
    /// hand-off. `FileManager.temporaryDirectory` is purged by the system, so
    /// transfers queued in a previous session can become un-replayable. Keeping
    /// the staged file in `Documents/PendingRouteTransfers/` keeps the queue
    /// durable; cleanup happens in `session(_:didFinish:error:)`.
    static var pendingRouteTransfersDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("PendingRouteTransfers", isDirectory: true)
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
    /// `summary` is the held ride snapshot from the phone (used to recover if the
    /// watch's local store is missing the entry). The callback MUST invoke the
    /// completion with `nil` on success or an error string on failure — the WC
    /// reply to the phone is sent based on that result.
    var onContinueHeldRideRequested: ((UUID, RideSummary?, @escaping (String?) -> Void) -> Void)?
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

        // Precompute the simplified elevation series here so the watch never has
        // to iterate the full point list to render its elevation chart.
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

    // MARK: - Voice Alert Ack (iOS → Watch)

    /// Phone-side: tell the watch we've started speaking utterance `id`.
    /// Fired from PhoneSpeechPlayer's didStart callback. The watch uses
    /// this ack to cancel its FallbackTimer for the same id. Best-effort —
    /// if the ack itself is lost, the watch's fallback will fire and
    /// double-speak; that's preferable to silence.
    func sendAlertAck(id: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else {
            // Watch unreachable from phone — rare during a mirrored workout.
            // Fall back to userInfo so the watch sees it eventually for
            // telemetry, but it won't help cancel the fallback (already fired
            // by then).
            WCSession.default.transferUserInfo(AlertAck(id: id).toDict())
            return
        }
        WCSession.default.sendMessage(
            AlertAck(id: id).toDict(),
            replyHandler: nil,
            errorHandler: { _ in /* best-effort, watch fallback will speak */ }
        )
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

    /// Tell the watch to continue a held ride. The full summary is included in the
    /// message so the watch can recover if its local RideStore lost the entry.
    /// `completion` reports actual success/failure based on the watch's reply —
    /// callers should surface failures to the user instead of silently assuming success.
    func sendContinueHeldRide(
        summary: RideSummary,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            completion(.failure(ConnectivityError.notReachable))
            return
        }

        let summaryJSON = (try? JSONEncoder().encode(summary))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let msg: [String: Any] = [
            "type": "continueHeldRide",
            "rideID": summary.id.uuidString,
            "summaryJSON": summaryJSON
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { reply in
                if let ok = reply["ok"] as? Bool, ok {
                    completion(.success(()))
                } else {
                    let reason = (reply["error"] as? String)
                        ?? "Watch could not continue the held ride."
                    completion(.failure(ConnectivityError.watchOperationFailed(reason)))
                }
            }, errorHandler: { error in
                // Queue via userInfo as a best-effort fallback, but surface failure
                // to the caller so the UI doesn't claim success.
                WCSession.default.transferUserInfo(msg)
                completion(.failure(error))
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            completion(.failure(ConnectivityError.notReachable))
        }
    }

    /// Finalize a held ride. The phone is authoritative — it already has the full
    /// ride data, so we mark the local copy complete immediately and tell the watch
    /// to delete its copy. No round-trip means End & Save can never silently fail
    /// because of a watch-side state mismatch.
    func sendFinalizeHeldRide(summary: RideSummary, rideStore: RideStore) {
        var completed = summary
        completed.isOnHold = nil
        completed.wasAutoFinalized = nil
        rideStore.update(completed)

        // Tell the watch to drop its copy. If unreachable, this queues via userInfo
        // and the watch will process it the next time WC delivers messages.
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": summary.id.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Tell the watch to discard a held ride and delete the phone's local copy.
    /// Uses the `deleteHeldRide` message rather than `discardRide`: the watch's
    /// `deleteHeldRide` handler deletes by rideID directly off the disk + RideStore,
    /// whereas `discardRide` relies on `rideStore.heldRide` being populated at the
    /// moment the message lands — which is racey on background wake.
    func sendDiscardRide(rideID: UUID) {
        deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
        DispatchQueue.main.async {
            if let store = self.rideStore,
               let ride = store.rides.first(where: { $0.id == rideID }) {
                store.delete(ride)
            }
        }
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": rideID.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Send acknowledgment to watch that a ride was successfully received.
    /// Mark that the phone is expecting a ride to start transferring from the watch.
    /// Shows a placeholder row in the ride list with a spinner. Auto-clears after
    /// a timeout if no transfer arrives.
    func markAwaitingIncomingRide() {
        DispatchQueue.main.async {
            self.isAwaitingIncomingRide = true
            self.awaitingIncomingRideTimeout?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.isAwaitingIncomingRide = false
            }
            self.awaitingIncomingRideTimeout = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: task)
        }
    }

    func clearAwaitingIncomingRide() {
        awaitingIncomingRideTimeout?.cancel()
        awaitingIncomingRideTimeout = nil
        if isAwaitingIncomingRide {
            isAwaitingIncomingRide = false
        }
    }

    /// Clear the `isOnHold` flag on a ride in the local store + on disk so the
    /// "On Hold" row disappears immediately when the watch resumes a held ride.
    /// The full updated summary arrives later via the normal transfer.
    func clearHeldFlag(rideID: UUID) {
        guard let store = self.rideStore,
              let ride = store.rides.first(where: { $0.id == rideID }),
              ride.onHold else { return }
        var updated = ride
        updated.isOnHold = nil
        store.update(updated)
    }

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

    // MARK: - Voice Alerts (Watch → Phone)
    //
    // Two transports per plan §3.4:
    //  • .immediate → sendMessage. Requires isReachable; failure is racey
    //    by design (watch caller arms a FallbackTimer alongside the send).
    //  • .soon → transferUserInfo. Guaranteed delivery, no reachability
    //    requirement, may arrive seconds later. Receiver enforces expiry.

    /// Send an alert that needs sub-second delivery. Returns immediately;
    /// failure modes:
    ///   • `isReachable == false` or `isCompanionAppInstalled == false`
    ///     → completion(false, .notReachable). Caller falls back to local.
    ///   • sendMessage errored synchronously
    ///     → completion(false, error). Caller falls back to local.
    ///   • Phone replied to the message
    ///     → completion(true, nil). (Note: this is NOT the speech ack —
    ///     the watch must still wait for `onAlertAckReceived` to be sure
    ///     the phone actually started speaking.)
    func sendImmediateAlert(_ payload: AlertPayload, completion: @escaping (Bool, Error?) -> Void) {
        guard WCSession.default.activationState == .activated else {
            completion(false, ConnectivityError.notActivated)
            return
        }
        guard WCSession.default.isCompanionAppInstalled else {
            completion(false, ConnectivityError.companionAppNotInstalled)
            return
        }
        guard WCSession.default.isReachable else {
            completion(false, ConnectivityError.notReachable)
            return
        }
        WCSession.default.sendMessage(
            payload.toDict(),
            replyHandler: { _ in completion(true, nil) },
            errorHandler: { error in completion(false, error) }
        )
    }

    /// Send an alert that can tolerate queued delivery (split announcements,
    /// stat readouts). Guaranteed eventual delivery; receiver drops on
    /// expiresAt.
    func sendQueuedAlert(_ payload: AlertPayload) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload.toDict())
    }

    /// Notify phone that a held ride was discarded on the watch so it can remove its copy.
    func sendDiscardRide(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": rideID.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Notify phone that a held ride is being resumed on the watch. The phone
    /// uses this to drop the "On Hold" row immediately; the eventual ride
    /// transfer (hold or end) re-introduces the updated summary.
    func sendRideContinued(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "rideContinued", "rideID": rideID.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

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

        // Notify phone that a file transfer is starting so it can show a progress indicator
        let summaryJSON = (try? JSONEncoder().encode(summary)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        WCSession.default.transferUserInfo([
            "type": "rideTransferStarting",
            "rideID": summary.id.uuidString,
            "summaryJSON": summaryJSON
        ])

        WCSession.default.transferFile(
            trackURL,
            metadata: [
                "type": "rideTrack",
                "summaryJSON": summaryJSON
            ]
        )

        print("Queued ride transfer: \(summary.name)")
    }

    private func saveRideLocally(summary: RideSummary, trackURL: URL) {
        let dir = Self.ridesDirectory

        // Copy track file — always overwrite so second/third holds accumulate correctly.
        // When finalizing a held ride the source IS the destination (the local copy in
        // ridesDirectory). Skip the copy in that case — removing then trying to copy a
        // file onto itself would just delete the track and silently fail the copy.
        let destTrack = dir.appendingPathComponent(summary.trackFilename)
        if trackURL.standardizedFileURL != destTrack.standardizedFileURL {
            try? FileManager.default.removeItem(at: destTrack)
            try? FileManager.default.copyItem(at: trackURL, to: destTrack)
        }

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

    #if os(iOS)
    /// Clean up staged route files once the OS reports the transfer is done
    /// (success or terminal failure). The staging directory survives relaunches,
    /// so a route queued while the phone was unreachable is still on disk when
    /// `WCSession` resumes the hand-off in a future session.
    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        let url = fileTransfer.file.fileURL
        let stagingDir = Self.pendingRouteTransfersDirectory.standardizedFileURL.path
        guard url.standardizedFileURL.path.hasPrefix(stagingDir) else { return }
        if let error = error {
            print("[Transfer] File transfer finished with error, leaving staged file in place: \(error)")
            return
        }
        try? FileManager.default.removeItem(at: url)
    }
    #endif

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

        // Voice alert via the queued path. Phone may receive these well
        // after they were sent (transferUserInfo is "guaranteed eventually")
        // so the receiver must check expiresAt and drop stale ones.
        #if os(iOS)
        if let payload = AlertPayload.fromDict(userInfo) {
            DispatchQueue.main.async {
                self.onVoiceAlertReceived?(payload)
            }
            return
        }
        #endif

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
                    let providedSummary: RideSummary? = {
                        guard let json = userInfo["summaryJSON"] as? String,
                              let data = json.data(using: .utf8) else { return nil }
                        return try? JSONDecoder().decode(RideSummary.self, from: data)
                    }()
                    DispatchQueue.main.async {
                        self.onContinueHeldRideRequested?(rideID, providedSummary) { _ in }
                    }
                }
            case "discardRide":
                DispatchQueue.main.async { self.onDiscardRideRequested?() }
            case "deleteHeldRide":
                if let idStr = userInfo["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
                    DispatchQueue.main.async {
                        if let store = self.rideStore,
                           let ride = store.rides.first(where: { $0.id == rideID }) {
                            store.delete(ride)
                        }
                        TransferLedger.shared.remove(rideID: rideID)
                    }
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

        #if os(iOS)
        // Watch is about to transfer a ride file — show it as pending in the ride list
        if let type = userInfo["type"] as? String,
           type == "rideTransferStarting",
           let idStr = userInfo["rideID"] as? String,
           let rideID = UUID(uuidString: idStr) {
            DispatchQueue.main.async {
                self.clearAwaitingIncomingRide()
                self.pendingTransferRideIDs.insert(rideID)
                // Also pre-populate the ride store with the summary so a row appears immediately
                if let jsonStr = userInfo["summaryJSON"] as? String,
                   let data = jsonStr.data(using: .utf8),
                   let summary = try? JSONDecoder().decode(RideSummary.self, from: data) {
                    if let store = self.rideStore,
                       !store.rides.contains(where: { $0.id == rideID }) {
                        store.rides.insert(summary, at: 0)
                    }
                }
            }
        }

        // Watch-initiated discard of a held ride, queued via userInfo when phone wasn't reachable
        if let type = userInfo["type"] as? String,
           type == "deleteHeldRide",
           let idStr = userInfo["rideID"] as? String,
           let rideID = UUID(uuidString: idStr) {
            deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
            DispatchQueue.main.async {
                if let store = self.rideStore,
                   let ride = store.rides.first(where: { $0.id == rideID }) {
                    store.delete(ride)
                }
            }
        }

        // Watch resumed a held ride (userInfo fallback if watch wasn't reachable
        // when the message was sent).
        if let type = userInfo["type"] as? String,
           type == "rideContinued",
           let idStr = userInfo["rideID"] as? String,
           let rideID = UUID(uuidString: idStr) {
            DispatchQueue.main.async {
                self.clearHeldFlag(rideID: rideID)
            }
        }
        #endif
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

        // Voice alert (watch → phone). The replyHandler returns
        // immediately so the watch knows the message was received; the
        // separate `didStart` ack (sent via sendMessage from iOS) is what
        // actually cancels the watch's fallback timer.
        #if os(iOS)
        if let payload = AlertPayload.fromDict(message) {
            DispatchQueue.main.async {
                self.onVoiceAlertReceived?(payload)
            }
            replyHandler(["received": true, "id": payload.id.uuidString])
            return
        }
        #endif

        // Voice alert ack (phone → watch). Phone fired didStart for a
        // specific utterance id.
        #if os(watchOS)
        if let ack = AlertAck.fromDict(message) {
            DispatchQueue.main.async {
                self.onAlertAckReceived?(ack.id)
            }
            replyHandler(["received": true])
            return
        }
        #endif

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
                guard let idStr = message["rideID"] as? String,
                      let rideID = UUID(uuidString: idStr) else {
                    replyHandler(["ok": false, "error": "Missing rideID"])
                    return
                }
                let providedSummary: RideSummary? = {
                    guard let json = message["summaryJSON"] as? String,
                          let data = json.data(using: .utf8) else { return nil }
                    return try? JSONDecoder().decode(RideSummary.self, from: data)
                }()
                DispatchQueue.main.async {
                    guard let cb = self.onContinueHeldRideRequested else {
                        replyHandler(["ok": false, "error": "Watch handler not registered"])
                        return
                    }
                    cb(rideID, providedSummary) { error in
                        if let error = error {
                            replyHandler(["ok": false, "error": error])
                        } else {
                            replyHandler(["ok": true])
                        }
                    }
                }
                return
            case "deleteHeldRide":
                if let idStr = message["rideID"] as? String, let rideID = UUID(uuidString: idStr) {
                    deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
                    DispatchQueue.main.async {
                        if let store = self.rideStore,
                           let ride = store.rides.first(where: { $0.id == rideID }) {
                            store.delete(ride)
                        }
                        TransferLedger.shared.remove(rideID: rideID)
                    }
                }
                replyHandler(["deleted": true])
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
        if let type = message["type"] as? String,
           type == "deleteHeldRide",
           let idStr = message["rideID"] as? String,
           let rideID = UUID(uuidString: idStr) {
            deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
            DispatchQueue.main.async {
                if let store = self.rideStore,
                   let ride = store.rides.first(where: { $0.id == rideID }) {
                    store.delete(ride)
                }
            }
            replyHandler(["deleted": true])
            return
        }
        // Watch resumed a held ride — drop the "On Hold" row immediately so the
        // user doesn't see a stale duplicate. The full updated summary will
        // arrive later via the normal ride transfer when the ride ends or is
        // held again.
        if let type = message["type"] as? String,
           type == "rideContinued",
           let idStr = message["rideID"] as? String,
           let rideID = UUID(uuidString: idStr) {
            DispatchQueue.main.async {
                self.clearHeldFlag(rideID: rideID)
            }
            replyHandler(["received": true])
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
        let existingWasHeld: Bool
        if let existingData = try? Data(contentsOf: summaryURL),
           let existingSummary = try? JSONDecoder().decode(RideSummary.self, from: existingData) {
            isRetransmit = true
            existingWasHeld = existingSummary.onHold
            // Preserve upload records from the existing version — the watch
            // doesn't know about uploads, so its summary always has uploads: nil
            if let existingUploads = existingSummary.uploads, !existingUploads.isEmpty {
                summary.uploads = existingUploads
            }
        } else {
            isRetransmit = false
            existingWasHeld = false
        }

        // A held ride being retransmitted with isOnHold cleared means the user
        // just finalized (or continued + ended). That's a completion event from
        // the integrations' point of view, so re-fire the new-ride hook even
        // though we've seen this ID before.
        let heldToCompleted = isRetransmit && existingWasHeld && !summary.onHold

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
            self.pendingTransferRideIDs.remove(summary.id)
            // A delivered ride (held or completed) supersedes the "waiting for ride
            // from watch" placeholder. Without this, the placeholder can linger
            // alongside the actual held-ride row until the awaiting timeout fires.
            self.clearAwaitingIncomingRide()
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary  // update existing (e.g. held → completed)
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
            print("Ride received: \(summary.name)\(isRetransmit ? " (retransmit)" : "")\(heldToCompleted ? " [finalized]" : "")")

            // Fire the new-ride hook for fresh rides and for held→completed
            // transitions. Plain retransmits of an already-completed ride are
            // ignored to avoid spamming auto-upload.
            if !isRetransmit || heldToCompleted {
                self.onRideReceived?(summary)
            }
        }

        // Send acknowledgment back to watch so it can mark the ride as confirmed
        sendRideAck(rideID: summary.id)
    }
    #endif

    func deleteLocalRide(rideID: UUID, dir: URL, fm: FileManager) {
        let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
        if let data = try? Data(contentsOf: summaryURL),
           let summary = try? JSONDecoder().decode(RideSummary.self, from: data) {
            let trackURL = dir.appendingPathComponent(summary.trackFilename)
            try? fm.removeItem(at: trackURL)
        }
        try? fm.removeItem(at: summaryURL)
        DispatchQueue.main.async {
            self.rideStore?.rides.removeAll { $0.id == rideID }
        }
    }
}
#endif // canImport(WatchConnectivity)
