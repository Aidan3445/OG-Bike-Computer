//
//  Connectivity.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

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

    func sendRoute(
        _ route: Route,
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
            WCSession.default.transferFile(tempURL, metadata: ["type": "route"])
            print("Queued file transfer: \(route.name) (\(data.count) bytes)")
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
}
#endif

// --- watchOS ---

#if os(watchOS)
extension ConnectivityManager {

    func sendRide(summary: RideSummary, trackURL: URL) {
        // Save locally on watch first
        saveRideLocally(summary: summary, trackURL: trackURL)

        guard WCSession.default.activationState == .activated else {
            print("Cannot send ride: WCSession not activated (saved locally)")
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

        // Copy track file
        let destTrack = dir.appendingPathComponent(summary.trackFilename)
        if !FileManager.default.fileExists(atPath: destTrack.path) {
            try? FileManager.default.copyItem(at: trackURL, to: destTrack)
        }

        // Save summary JSON
        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL)
        }

        // Update in-memory store if attached
        DispatchQueue.main.async {
            if let store = self.rideStore,
               !store.rides.contains(where: { $0.id == summary.id }) {
                store.rides.insert(summary, at: 0)
            }
        }

        print("Ride saved locally on watch: \(summary.name)")
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
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
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
        DispatchQueue.main.async {
            if let existing = self.routeStore?.routes.first(where: { $0.name == route.name }) {
                self.routeStore?.delete(existing)
            }
            self.routeStore?.save(route)
            self.routeStore.map { self.reportRoutes($0.routes) }
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

        #if os(iOS)
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
              let summary = try? JSONDecoder().decode(RideSummary.self, from: summaryData) else {
            print("Failed to decode ride summary")
            return
        }

        // Save directly to the rides directory — works whether rideStore is attached or not
        let dir = Self.ridesDirectory

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

        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL)
        }

        // If rideStore is attached, update in-memory immediately
        DispatchQueue.main.async {
            if let store = self.rideStore,
               !store.rides.contains(where: { $0.id == summary.id }) {
                store.rides.insert(summary, at: 0)
            }
            print("Ride received: \(summary.name)")
        }
    }
    #endif
}
