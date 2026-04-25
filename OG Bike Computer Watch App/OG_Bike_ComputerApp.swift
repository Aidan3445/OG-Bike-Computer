//
//  OG_Bike_ComputerApp.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import HealthKit
import SwiftUI
import WatchKit

// MARK: - Extension Delegate

class ExtensionDelegate: NSObject, WKApplicationDelegate {
    let store = RouteStore()
    let rideStore = RideStore()
    let metricConfig = MetricConfigStore()
    let workout = WorkoutManager()

    func applicationDidFinishLaunching() {
        ConnectivityManager.shared.activate()
        ConnectivityManager.shared.attachStores(routeStore: store, rideStore: rideStore)

        workout.rideStore = rideStore

        // Wire up WC ride command handlers immediately so they're ready
        // even before ContentView loads. This handles the case where iOS
        // sends a startRide WC message alongside startWatchApp.
        ConnectivityManager.shared.onStartRideRequested = { [weak self] (routeID: UUID?, activity: ActivityType) in
            guard let self = self else { return }
            guard !self.workout.isActive else { return }
            if let routeID = routeID,
               let route = self.store.routes.first(where: { $0.id == routeID }) {
                self.workout.loadRoute(route)
            }
            self.workout.start(activity: activity)
        }

        ConnectivityManager.shared.onChangeRouteRequested = { [weak self] routeID in
            guard let self = self, self.workout.isActive else { return }
            if let routeID, let route = self.store.routes.first(where: { $0.id == routeID }) {
                self.workout.loadRoute(route)
            } else {
                self.workout.clearRoute()
            }
        }

        ConnectivityManager.shared.onDiscardRideRequested = { [weak self] in
            guard let self = self, self.workout.isActive else { return }
            self.workout.discard()
        }

        ConnectivityManager.shared.onHoldRideRequested = { [weak self] in
            guard let self = self, self.workout.isActive else { return }
            self.workout.holdRide()
        }

        ConnectivityManager.shared.onContinueHeldRideRequested = { [weak self] rideID in
            guard let self = self, !self.workout.isActive else { return }
            guard let held = self.rideStore.heldRide, held.id == rideID else { return }
            self.workout.continueHeldRide(summary: held)
        }

        ConnectivityManager.shared.onFinalizeHeldRideRequested = { [weak self] rideID in
            guard let self = self, !self.workout.isActive else { return }
            guard let held = self.rideStore.heldRide, held.id == rideID else { return }
            self.workout.finalizeHeldRide(summary: held)
        }

        workout.recoverCheckpointIfNeeded()
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

    /// Called when iOS triggers `HKHealthStore().startWatchApp(with:)`.
    /// The system launches/foregrounds the watch app and delivers the configuration here.
    /// Route loading is handled separately via the WC message handler (onStartRideRequested).
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let activityType = ActivityType(hkType: workoutConfiguration.activityType)

        Task { @MainActor in
            guard !workout.isActive else { return }
            workout.start(activity: activityType)
        }
    }
}

@main
struct OG_Bike_ComputerApp: App {
    @WKApplicationDelegateAdaptor(ExtensionDelegate.self) var delegate

    var body: some Scene {
        WindowGroup {
            ContentView(store: delegate.store, rideStore: delegate.rideStore, metricConfig: delegate.metricConfig, workout: delegate.workout)
        }
    }
}
