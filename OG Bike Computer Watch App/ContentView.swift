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
    @StateObject private var simulator = RideSimulator()

    @State private var showDiscardAlert = false

    var body: some View {
        Group {
            if workout.isActive {
                if workout.isSimulating {
                    SimPlaybackOverlay(simulator: simulator, workout: workout)
                } else {
                    WorkoutView(workout: workout, metricConfig: metricConfig, onStop: handleStop) {
                        MidRideRouteList(store: store, workout: workout)
                    }
                }
            } else {
                RouteList(store: store, workout: workout, simulator: simulator)
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
                workout.navigation.offRouteThreshold = navPrefs.navigationEvents.offRouteThreshold
            }

            ConnectivityManager.shared.onUserSettingsReceived = { data in
                guard let settings = try? JSONDecoder().decode(UserSettings.self, from: data) else { return }
                workout.riderMass = settings.riderWeight
                workout.bikeMass = settings.bikeWeight
                UnitState.shared.preferences = settings.unitPreferences
                VoiceNavigator.shared.preferences = settings.navigationAlerts
                workout.navigation.offRouteThreshold = settings.navigationAlerts.navigationEvents.offRouteThreshold
                // Cache for next boot
                if let encoded = try? JSONEncoder().encode(settings.unitPreferences) {
                    UserDefaults.standard.set(encoded, forKey: "unitPreferences")
                }
                if let encoded = try? JSONEncoder().encode(settings.navigationAlerts) {
                    UserDefaults.standard.set(encoded, forKey: "navigationAlerts")
                }
            }

            workout.onRideCompleted = { summary in
                rideStore.save(summary)
            }
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
    }

    private func handleStop() {
        if workout.movingTime < 60 {
            showDiscardAlert = true
        } else {
            workout.stop(save: true)
        }
    }
}
