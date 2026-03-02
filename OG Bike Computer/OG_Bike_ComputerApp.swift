//
//  OG_Bike_ComputerApp.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI

class AppDelegate: NSObject, UIApplicationDelegate {
    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ConnectivityManager.shared.activate()
        return true
    }
}

@main
struct OG_Bike_ComputerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var routeStore = RouteStore()
    @StateObject private var rideStore = RideStore()
    
    @State private var importedFileURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(routeStore: routeStore, rideStore: rideStore)
                .onAppear {
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                }
                .onOpenURL { url in
                    handleIncomingFile(url)
                }
        }
    }

    private func handleIncomingFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importFile(at: url)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        importFile(at: url)
    }

    private func importFile(at url: URL) {
            guard let data = try? Data(contentsOf: url) else {
                print("Could not read shared file: \(url)")
                return
            }

            let parser = GPXParser()
            let parsed = parser.parse(data: data)

            for route in parsed {
                routeStore.save(route)
            }

            if !parsed.isEmpty {
                print("Imported \(parsed.count) route(s) from share sheet")
            }
        }
}
