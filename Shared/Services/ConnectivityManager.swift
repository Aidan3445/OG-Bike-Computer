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
    @Published var lastEvent: String = "none"

    var onRouteReceived: ((Route) -> Void)?

    #if os(watchOS)
    @Published var routeStore: RouteStore?
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
}

#if os(iOS)
extension ConnectivityManager {

    func requestWatchSync() {
        guard WCSession.default.activationState == .activated else { return }
        let ctx = WCSession.default.receivedApplicationContext

        if let names = ctx["watchRouteNames"] as? [String] {
            DispatchQueue.main.async {
                self.routeNamesOnWatch = Set(names)
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

#if os(watchOS)
extension ConnectivityManager {

    func sendRide(summary: RideSummary, trackURL: URL) {
        guard WCSession.default.activationState == .activated else {
            print("Cannot send ride: WCSession not activated")
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

    func reportRoutes(_ routes: [Route]) {
        guard WCSession.default.activationState == .activated else { return }
        let names = routes.map { $0.name }
        try? WCSession.default.updateApplicationContext(["watchRouteNames": names])
    }
}
#endif

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
        if let names = applicationContext["watchRouteNames"] as? [String] {
            DispatchQueue.main.async {
                self.routeNamesOnWatch = Set(names)
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
        }
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
              let summary = try? JSONDecoder().decode(RideSummary.self, from: summaryData),
              let rideStore = rideStore else {
            print("Failed to decode ride summary")
            return
        }

        let destURL = rideStore.directory.appendingPathComponent(summary.trackFilename)

        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)
        } catch {
            print("Failed to copy track file: \(error)")
            return
        }

        DispatchQueue.main.async {
            rideStore.save(summary)
            print("Ride saved: \(summary.name)")
        }
    }
    #endif
}
