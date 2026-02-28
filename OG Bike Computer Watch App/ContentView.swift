//
//  ContentView.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RouteStore()
    @StateObject private var connectivity = ConnectivityManager.shared
    @StateObject private var workout = WorkoutManager()

    @State private var showDiscardAlert = false

    var body: some View {
        Group {
            if workout.isActive {
                WorkoutView(workout: workout, onStop: handleStop)
            } else {
                routeList
            }
        }
        .onAppear {
            workout.requestPermissions()
            ConnectivityManager.shared.onRouteReceived = { route in
                store.save(route)
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
        if workout.elapsedTime < 60 {
            showDiscardAlert = true
        } else {
            workout.stop(save: true)
        }
    }

    private var routeList: some View {
        NavigationStack {
            Group {
                if store.routes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Routes")
                            .font(.headline)
                        Text("Import a GPX on your iPhone and send it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(store.routes) { route in
                            NavigationLink(value: route) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                        .font(.headline)
                                    Text(formatDistance(route.distance))
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .onDelete { indices in
                            for i in indices {
                                store.delete(store.routes[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Routes")
            .navigationDestination(for: Route.self) { route in
                StartRideView(route: route, workout: workout)
            }
        }
    }
}

#Preview {
    ContentView()
}
