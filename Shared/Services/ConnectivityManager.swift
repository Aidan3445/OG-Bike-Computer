//
//  Connectivity.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import WatchConnectivity
import Combine

class ConnectivityManager: NSObject, ObservableObject, WCSessionDelegate {
    static let shared = ConnectivityManager()

    @Published var isReachable = false
    @Published var activationState: WCSessionActivationState = .notActivated
    @Published var isPaired: Bool = false
    @Published var isWatchAppInstalled: Bool = false
    @Published var routeNamesOnWatch: Set<String> = []
    
    @Published var lastEvent: String = "none"

    var onRouteReceived: ((Route) -> Void)?

    #if os(watchOS)
    private var routeStore: RouteStore?

    func attach(store: RouteStore) {
        self.routeStore = store
        reportRoutes(store.routes)
    }
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

        guard session.isReachable else {
            return .failure(.notReachable)
        }

        return .success(())
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
            completion(.success(()))
        } catch {
            completion(.failure(error))
        }
    }
    
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
            #endif
        }
    }
    
    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        print("Received file transfer")

        guard let data = try? Data(contentsOf: file.fileURL),
              let route = try? JSONDecoder().decode(Route.self, from: data) else {
            print("Failed to decode transferred file")
            return
        }

        print("Decoded route: \(route.name)")

        #if os(watchOS)
        DispatchQueue.main.async {
            if let existing = self.routeStore?.routes.first(where: { $0.name == route.name }) {
                self.routeStore?.delete(existing)
            }
            self.routeStore?.save(route)
            if let routes = self.routeStore?.routes {
                self.reportRoutes(routes)
            }
        }
        #endif
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
                self.lastEvent = "decoded: \(route.name)"
                self.onRouteReceived?(route)
            }
        }
    }

    func session(_ session: WCSession,
             didReceiveApplicationContext applicationContext: [String: Any]) {
        if let names = applicationContext["watchRouteNames"] as? [String] {
            DispatchQueue.main.async {
                self.routeNamesOnWatch = Set(names)
            }
        }
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }
    }

    #if os(iOS)
    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        // Re-activate after switching watches
        WCSession.default.activate()
    }
    #endif

    #if os(watchOS)
    func reportRoutes(_ routes: [Route]) {
        guard WCSession.default.activationState == .activated else { return }
        let names = routes.map { $0.name }
        try? WCSession.default.updateApplicationContext(["watchRouteNames": names])
    }
    #endif
}
