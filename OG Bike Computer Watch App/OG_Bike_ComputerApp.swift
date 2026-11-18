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
        ResourceMonitor.shared.start(workout: workout)

        // Wire up WC ride command handlers immediately so they're ready
        // even before ContentView loads. This handles the case where iOS
        // sends a startRide WC message alongside startWatchApp.
        ConnectivityManager.shared.onStartRideRequested = { [weak self] (routeID: UUID?, activity: ActivityType) in
            guard let self = self else { return }
            self.workout.dismissSummaryIfShowing()
            guard !self.workout.isActive else { return }
            // A held ride is allowed to coexist with a new active ride. The
            // rider only has to resolve the conflict when they later try to
            // hold this ride — see `WorkoutManager.attemptHold`.
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
            guard let self = self else { return }
            self.workout.dismissSummaryIfShowing()
            // Discard works in two modes:
            //   1. Active ride → tear down via WorkoutManager.discard()
            //   2. Held ride (workout not active) → delete the held ride from disk + store
            if self.workout.isActive {
                self.workout.discard()
            } else if let held = self.rideStore.heldRide {
                self.workout.discardHeldRide(summary: held)
            }
        }

        ConnectivityManager.shared.onHoldRideRequested = { [weak self] in
            guard let self = self, self.workout.isActive else { return }
            self.workout.attemptHold()
        }

        ConnectivityManager.shared.onPauseRideRequested = { [weak self] in
            guard let self, self.workout.isActive, !self.workout.isPaused else { return }
            self.workout.pause()
        }

        ConnectivityManager.shared.onResumeRideRequested = { [weak self] in
            guard let self, self.workout.isActive, self.workout.isPaused else { return }
            self.workout.resume()
        }

        // Same as the session ending from the phone. The phone already
        // turned short rides into a discard.
        ConnectivityManager.shared.onEndRideRequested = { [weak self] in
            guard let self, self.workout.isActive, self.workout.completedRideSummary == nil else { return }
            self.workout.stop(save: true)
        }

        ConnectivityManager.shared.onPhoneMirrorAttached = { [weak self] in
            self?.workout.stopEarlyTelemetry()
        }

        ConnectivityManager.shared.onSampleHapticRequested = { intensity in
            let haptic: WKHapticType
            switch intensity {
            case "light":  haptic = .click
            case "strong": haptic = .notification
            default:       haptic = .directionUp
            }
            WKInterfaceDevice.current().play(haptic)
        }

        ConnectivityManager.shared.onContinueHeldRideRequested = { [weak self] rideID, providedSummary, ack in
            guard let self = self else {
                ack("Watch app not ready")
                return
            }
            self.workout.dismissSummaryIfShowing()
            if self.workout.isActive {
                ack("A workout is already in progress on the watch")
                return
            }

            // Resolve the held ride: prefer the watch's own store, fall back to the
            // summary the phone sent in the message. This handles the case where the
            // watch's RideStore lost the entry but the phone still has it.
            let held: RideSummary
            if let existing = self.rideStore.heldRide, existing.id == rideID {
                held = existing
            } else if let provided = providedSummary, provided.id == rideID {
                self.rideStore.save(provided)
                held = provided
            } else {
                ack("Held ride not found on watch")
                return
            }

            // Continuation needs the track file to restore stats. If it's missing on
            // the watch, fail explicitly rather than silently dropping the request.
            let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(held.trackFilename)
            guard FileManager.default.fileExists(atPath: trackURL.path) else {
                ack("Track file missing on watch — cannot continue")
                return
            }

            let route = held.heldRouteID.flatMap { id in
                self.store.routes.first { $0.id == id }
            }
            self.workout.continueHeldRide(summary: held, route: route)
            ack(nil)
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

    /// Called when the phone launches the app with `HKHealthStore().startWatchApp(with:)`.
    /// The phone's message is the real command. When a ride is held the phone may be
    /// resuming it, so leave the start to that message instead of opening a second ride.
    func handle(_ workoutConfiguration: HKWorkoutConfiguration) {
        let activityType = ActivityType(hkType: workoutConfiguration.activityType)

        Task { @MainActor in
            workout.dismissSummaryIfShowing()
            guard !workout.isActive, rideStore.heldRide == nil else { return }
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
