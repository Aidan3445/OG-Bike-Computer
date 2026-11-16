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
    @ObservedObject var workout: WorkoutManager
    #if DEBUG
    @StateObject private var simulator = RideSimulator()
    #endif

    @State private var showDiscardAlert = false
    @State private var routeListShowingDetail = false
    @State private var homePage = 0

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
                // Vertical paging so the Digital Crown switches between Routes and
                // History. Horizontal page swiping would fight with the List
                // swipe-to-delete gesture on individual route rows. History is
                // only reachable from the route list itself, not from a pushed screen.
                // Both pages always stay in the TabView. Adding or removing one
                // while a screen is pushed breaks that screen's back button, so
                // History bounces back to Routes instead.
                TabView(selection: $homePage) {
                    #if DEBUG
                    RouteList(store: store, rideStore: rideStore, workout: workout, simulator: simulator,
                              isShowingDetail: $routeListShowingDetail)
                        .tag(0)
                    #else
                    RouteList(store: store, rideStore: rideStore, workout: workout,
                              isShowingDetail: $routeListShowingDetail)
                        .tag(0)
                    #endif

                    WatchRideHistoryView(rideStore: rideStore, connectivity: connectivity)
                        .tag(1)
                }
                .tabViewStyle(.verticalPage)
                .onChange(of: homePage) { _, page in
                    if page != 0, routeListShowingDetail {
                        withAnimation { homePage = 0 }
                    }
                }
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

            ConnectivityManager.shared.onToggleVoiceRequested = {
                VoiceNavigator.shared.isEnabled.toggle()
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
        .alert("Ride Recovered", isPresented: Binding(
            get: { workout.recoveredRideSummary != nil },
            set: { if !$0 { workout.recoveredRideSummary = nil } }
        )) {
            Button("OK") { workout.recoveredRideSummary = nil }
        } message: {
            if let ride = workout.recoveredRideSummary {
                Text("\"\(ride.name)\" was saved as a held ride — tap it in the route list to continue or finish.")
            }
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
        // Ignore a stop that arrives after the ride already ended or while the prompt is up.
        guard workout.isActive, workout.completedRideSummary == nil, !showDiscardAlert else { return }
        if workout.movingTime < 60 {
            showDiscardAlert = true
        } else {
            workout.stop(save: true)
        }
    }
}
