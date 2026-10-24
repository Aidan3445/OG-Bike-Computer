//
//  ConnectivityManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import Combine

/// Owns the WCSession on both devices. Incoming traffic is routed in
/// ConnectivityManager+Session, and each feature's sending and receiving
/// lives in its own extension file next to this one.
final class ConnectivityManager: NSObject, ObservableObject {
    static let shared = ConnectivityManager()

    @Published var isReachable = false
    @Published var activationState: WCSessionActivationState = .notActivated
    @Published var isPaired = false
    @Published var isWatchAppInstalled = false
    @Published var routeIDsOnWatch: Set<UUID> = []
    @Published var watchStorageSize: Int64 = 0
    @Published var lastEvent: String = "none"

    var onRouteReceived: ((Route) -> Void)?
    var onMetricConfigReceived: ((Data) -> Void)?
    var onUserSettingsReceived: ((Data) -> Void)?

    #if os(iOS)
    @Published var rideStore: RideStore?
    /// A voice alert arrived from the watch. PhoneAlertReceiver decides what to do with it.
    var onVoiceAlertReceived: ((AlertPayload) -> Void)?
    var onRideReceived: ((RideSummary) -> Void)?
    /// The watch is ending the ride as "held" or "discarded". This arrives
    /// before the mirrored session ends so the Live Activity can show the
    /// right banner instead of the default completed one.
    var onWatchTerminalIntent: ((String) -> Void)?
    /// Rides whose files are on their way from the watch.
    @Published var pendingTransferRideIDs: Set<UUID> = []
    /// The watch ended a ride but its transfer hasn't started yet. Drives the
    /// placeholder row in the ride list.
    @Published var isAwaitingIncomingRide: Bool = false
    var awaitingIncomingRideTimeout: DispatchWorkItem?
    #endif

    #if os(watchOS)
    @Published var routeStore: RouteStore?
    @Published var rideStore: RideStore?
    /// Rides whose files are queued or transferring to the phone.
    @Published var inFlightTransferRideIDs: Set<UUID> = []

    /// Whether the phone still has a ride the watch thinks it delivered.
    enum PhonePresence {
        case unknown
        case checking
        case present
        /// The phone acked the ride but no longer has it. The watch shows an
        /// error icon and offers a retry.
        case missing
    }
    /// Cached until the app relaunches.
    @Published var phonePresenceByRide: [UUID: PhonePresence] = [:]

    /// The phone started speaking this alert.
    var onAlertAckReceived: ((UUID) -> Void)?
    /// The phone finished speaking this alert, so the next queued line can play.
    var onAlertFinishReceived: ((UUID) -> Void)?
    #endif

    // Commands from the phone, handled on the watch.
    var onStartRideRequested: ((UUID?, ActivityType) -> Void)?
    var onChangeRouteRequested: ((UUID?) -> Void)?
    var onDiscardRideRequested: (() -> Void)?
    var onToggleVoiceRequested: (() -> Void)?
    var onHoldRideRequested: (() -> Void)?
    /// Plays a sample buzz for an intensity like "light", "medium" or "strong".
    var onSampleHapticRequested: ((String) -> Void)?
    /// Resumes a held ride. The summary is the phone's copy, used if the
    /// watch lost its own. Call the completion with nil on success or an
    /// error message, since the reply to the phone waits on it.
    var onContinueHeldRideRequested: ((UUID, RideSummary?, @escaping (String?) -> Void) -> Void)?

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

    /// Ride summaries and tracks. Works before a RideStore is attached.
    static var ridesDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("rides", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Route files waiting to go to the watch. This lives in Documents rather
    /// than tmp because WatchConnectivity retries queued transfers after a
    /// relaunch and the file has to still be there.
    static var pendingRouteTransfersDirectory: URL {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let dir = docs.appendingPathComponent("PendingRouteTransfers", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func rideID(in payload: [String: Any]) -> UUID? {
        (payload["rideID"] as? String).flatMap { UUID(uuidString: $0) }
    }

    func processOutstandingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        #if os(iOS)
        let outstanding = WCSession.default.outstandingFileTransfers
        print("Outstanding file transfers: \(outstanding.count)")
        #endif
    }

    /// Deletes a ride's summary and track from `dir` and drops it from the store.
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
#endif
