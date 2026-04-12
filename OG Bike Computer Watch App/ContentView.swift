//
//  ContentView.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI

struct ContentView: View {
    @ObservedObject var store: RouteStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject var metricConfig: MetricConfigStore
    @StateObject private var connectivity = ConnectivityManager.shared
    @StateObject private var workout = WorkoutManager()
    #if DEBUG
    @StateObject private var simulator = RideSimulator()
    #endif

    @State private var showDiscardAlert = false

    var body: some View {
        Group {
            if workout.isActive {
                if let summary = workout.completedRideSummary {
                    RideSummaryView(summary: summary, onDismiss: {
                        workout.dismissSummary()
                    })
                } else if workout.isSimulating {
                    #if DEBUG
                    SimPlaybackOverlay(simulator: simulator, workout: workout)
                    #endif
                } else {
                    WorkoutView(workout: workout, metricConfig: metricConfig, onStop: handleStop) {
                        MidRideRouteList(store: store, workout: workout)
                    }
                }
            } else {
                #if DEBUG
                RouteList(store: store, workout: workout, simulator: simulator)
                #else
                RouteList(store: store, workout: workout)
                #endif
            }
        }
        .onAppear {
            workout.requestPermissions()
            ConnectivityManager.shared.attachStores(routeStore: store, rideStore: rideStore)

            store.onChange = {
                ConnectivityManager.shared.reportRoutes(store.routes)
            }

            ConnectivityManager.shared.onMetricConfigReceived = { data in
                metricConfig.applyFromRemote(data)
            }

            // Restore cached unit preferences on boot
            if let cached = UserDefaults.standard.data(forKey: "unitPreferences"),
               let prefs = try? JSONDecoder().decode(UnitPreferences.self, from: cached) {
                UnitState.shared.preferences = prefs
            }
            // Restore cached navigation alert preferences on boot
            if let cached = UserDefaults.standard.data(forKey: "navigationAlerts"),
               let navPrefs = try? JSONDecoder().decode(NavigationAlertPreferences.self, from: cached) {
                VoiceNavigator.shared.preferences = navPrefs
                workout.navigationAlerts = navPrefs
                workout.navigation.offRouteThreshold = navPrefs.navigationEvents.offRouteThreshold
            }
            // Restore cached ride preferences on boot
            if let cached = UserDefaults.standard.data(forKey: "ridePreferences"),
               let ridePrefs = try? JSONDecoder().decode(RidePreferences.self, from: cached) {
                workout.ridePreferences = ridePrefs
                workout.navigation.offRouteGraceSamples = ridePrefs.offRouteGraceSamples
            }
            // Restore cached healthKitAutoUpload on boot
            if UserDefaults.standard.object(forKey: "healthKitAutoUpload") != nil {
                workout.healthKitAutoUpload = UserDefaults.standard.bool(forKey: "healthKitAutoUpload")
            }

            ConnectivityManager.shared.onUserSettingsReceived = { data in
                guard let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else { return }
                workout.riderMass = settings.riderWeight
                workout.bikeMass = settings.bikeWeight
                UnitState.shared.preferences = settings.unitPreferences
                VoiceNavigator.shared.preferences = settings.navigationAlerts
                workout.navigationAlerts = settings.navigationAlerts
                workout.navigation.offRouteThreshold = settings.navigationAlerts.navigationEvents.offRouteThreshold
                workout.ridePreferences = settings.ridePreferences
                workout.navigation.offRouteGraceSamples = settings.ridePreferences.offRouteGraceSamples
                workout.healthKitAutoUpload = settings.healthKitAutoUpload
                // Cache for next boot
                if let encoded = try? JSONEncoder().encode(settings.unitPreferences) {
                    UserDefaults.standard.set(encoded, forKey: "unitPreferences")
                }
                if let encoded = try? JSONEncoder().encode(settings.navigationAlerts) {
                    UserDefaults.standard.set(encoded, forKey: "navigationAlerts")
                }
                if let encoded = try? JSONEncoder().encode(settings.ridePreferences) {
                    UserDefaults.standard.set(encoded, forKey: "ridePreferences")
                }
                UserDefaults.standard.set(settings.healthKitAutoUpload, forKey: "healthKitAutoUpload")
            }

            workout.onRideCompleted = { summary in
                rideStore.save(summary)
            }

            // Handle ride commands from phone (Shortcuts/Siri)
            ConnectivityManager.shared.onStartRideRequested = { (routeID: UUID?, activity: ActivityType) in
                guard !workout.isActive else { return }
                if let routeID = routeID,
                   let route = store.routes.first(where: { $0.id == routeID }) {
                    workout.loadRoute(route)
                }
                workout.start(activity: activity)
            }

            ConnectivityManager.shared.onChangeRouteRequested = { routeID in
                guard workout.isActive,
                      let route = store.routes.first(where: { $0.id == routeID }) else { return }
                workout.loadRoute(route)
            }

            ConnectivityManager.shared.onDiscardRideRequested = {
                guard workout.isActive else { return }
                workout.discard()
            }

            ConnectivityManager.shared.onToggleVoiceRequested = {
                VoiceNavigator.shared.isEnabled.toggle()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonStartRide)) { notification in
            guard !workout.isActive else { return }
            let activity = notification.object as? ActivityType ?? .cycling
            workout.start(activity: activity)
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonPauseRide)) { _ in
            guard workout.isActive, !workout.isPaused else { return }
            workout.pause()
        }
        .onReceive(NotificationCenter.default.publisher(for: .actionButtonResumeRide)) { _ in
            guard workout.isActive, workout.isPaused else { return }
            workout.resume()
        }
        .alert("Discard Ride?", isPresented: $showDiscardAlert) {
            Button("Discard", role: .destructive) {
                workout.discard()
            }
            Button("Save Anyway") {
                workout.stop(save: true)
            }
        } message: {
            Text("This ride is under 1 minute. Do you want to save it anyway?")
        }
        .alert("Save to Apple Health?", isPresented: $workout.showHealthKitPrompt) {
            Button("Save") {
                workout.healthKitPromptHandler?(true)
                workout.healthKitPromptHandler = nil
            }
            Button("Don't Save", role: .destructive) {
                workout.healthKitPromptHandler?(false)
                workout.healthKitPromptHandler = nil
            }
        } message: {
            Text("Auto-upload to Apple Health is off. Save this workout to Apple Health anyway?")
        }
    }

    private func handleStop() {
        if workout.movingTime < 60 {
            showDiscardAlert = true
        } else {
            workout.stop(save: true)
        }
    }
}
