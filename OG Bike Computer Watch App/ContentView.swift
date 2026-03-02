//
//  ContentView.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//


import SwiftUI

struct ContentView: View {
    @ObservedObject var store = RouteStore()
    @StateObject private var connectivity = ConnectivityManager.shared
    @StateObject private var workout = WorkoutManager()

    @State private var showDiscardAlert = false

    var body: some View {
        Group {
            if workout.isActive {
                WorkoutView(workout: workout, onStop: handleStop)
            } else {
                RouteList(store: store, workout: workout)
            }
        }
        .onAppear {
            workout.requestPermissions()
            ConnectivityManager.shared.attachStores(routeStore: store)

            store.onChange = {
                ConnectivityManager.shared.reportRoutes(store.routes)
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

#Preview {
    ContentView()
}
