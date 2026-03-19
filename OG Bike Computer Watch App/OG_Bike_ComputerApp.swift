//
//  OG_Bike_ComputerApp.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI
import WatchKit

class ExtensionDelegate: NSObject, WKApplicationDelegate {
    let store = RouteStore()
    let rideStore = RideStore()

    func applicationDidFinishLaunching() {
        ConnectivityManager.shared.activate()
        ConnectivityManager.shared.attachStores(routeStore: store, rideStore: rideStore)
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let connectivityTask as WKWatchConnectivityRefreshBackgroundTask:
                connectivityTask.setTaskCompletedWithSnapshot(false)
            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}

@main
struct OG_Bike_ComputerApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(store: delegate.store, rideStore: delegate.rideStore)
        }
    }
}
