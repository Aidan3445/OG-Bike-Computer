//
//  RouteList.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct RouteList: View {
    @ObservedObject var store: RouteStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject var workout: WorkoutManager
    #if DEBUG
    @ObservedObject var simulator: RideSimulator
    #endif
    @ObservedObject private var unitState = UnitState.shared

    @State private var showHeldRideAlert = false
    @State private var showDiscardConfirmation = false

    var body: some View {
        let _ = unitState.preferences // register dependency so list re-renders on unit change
        NavigationStack {
            Group {
                if store.routes.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Image(systemName: "arrow.down.circle")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No Routes")
                                .font(.headline)
                            Text("Import from phone")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)

                            Divider().padding(.vertical, 4)

                            if let held = rideStore.heldRide {
                                heldRideButton(held)
                            }

                            NavigationLink {
                                StartRideView(route: nil, workout: workout, rideStore: rideStore)
                            } label: {
                                Label("Free Ride", systemImage: "record.circle")
                                    .frame(maxWidth: .infinity)
                            }
                            .tint(.orange)
                        }
                        .padding()
                    }
                } else {
                    List {
                        if let held = rideStore.heldRide {
                            heldRideButton(held)
                        }

                        NavigationLink {
                            StartRideView(route: nil, workout: workout, rideStore: rideStore)
                        } label: {
                            Label("Free Ride", systemImage: "record.circle")
                                .foregroundStyle(.orange)
                        }

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

                        #if DEBUG
                        NavigationLink {
                            SimulationView(store: store, workout: workout, simulator: simulator)
                        } label: {
                            Label("Simulate", systemImage: "play.circle")
                        }
                        #endif

                        VStack(spacing: 2) {
                            Text(formattedStorageSize(store.storageSize))
                            Text(appVersionString)
                        }
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .listRowBackground(Color.clear)
                            .listRowInsets(EdgeInsets())
                            .padding(.all, 0)
                            .frame(maxWidth: .infinity, alignment: .center)
                    }
                    .id(unitState.preferences)
                    .navigationTitle("Routes")
                    .navigationDestination(for: Route.self) { route in
                        StartRideView(route: route, workout: workout, rideStore: rideStore)
                    }
                }
            }
        }
    }

    private var appVersionString: String {
        let info = Bundle.main.infoDictionary
        let version = info?["CFBundleShortVersionString"] as? String ?? "?"
        let build = info?["CFBundleVersion"] as? String ?? "?"
        return "v\(version) (\(build))"
    }

    @ViewBuilder
    private func heldRideButton(_ held: RideSummary) -> some View {
        Button {
            showHeldRideAlert = true
        } label: {
            Label("Resume Ride", systemImage: "hand.raised.fill")
                .foregroundStyle(.orange)
        }
        .alert("Held Ride", isPresented: $showHeldRideAlert) {
            Button("Continue") {
                let route = held.heldRouteID.flatMap { id in
                    store.routes.first { $0.id == id }
                }
                workout.continueHeldRide(summary: held, route: route)
            }
            Button("End & Save") { workout.finalizeHeldRide(summary: held) }
            Button("Discard", role: .destructive) { showDiscardConfirmation = true }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\(held.name) • \(formatDistance(held.distance))")
        }
        .alert("Discard Held Ride?", isPresented: $showDiscardConfirmation) {
            Button("Discard", role: .destructive) {
                workout.discardHeldRide(summary: held)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This will permanently delete your held ride. This cannot be undone.")
        }
    }
}
