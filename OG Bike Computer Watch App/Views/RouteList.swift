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
                    VStack(spacing: 8) {
                        if let held = rideStore.heldRide {
                            heldRideButton(held)
                            Divider().padding(.vertical, 4)
                        }

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

                        NavigationLink {
                            StartRideView(route: nil, workout: workout, rideStore: rideStore)
                        } label: {
                            Label("Free Ride", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.orange)
                    }
                    .padding()
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

                        Text(formattedStorageSize(store.storageSize))
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

    @ViewBuilder
    private func heldRideButton(_ held: RideSummary) -> some View {
        Button {
            showHeldRideAlert = true
        } label: {
            Label("Resume Ride", systemImage: "hand.raised.fill")
                .foregroundStyle(.orange)
        }
        .alert("Held Ride", isPresented: $showHeldRideAlert) {
            Button("Continue") { workout.continueHeldRide(summary: held) }
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
        // Phone-initiated start that needs confirmation (held ride would be discarded)
        .alert("Discard Held Ride?", isPresented: Binding(
            get: { workout.pendingStartConfirmation != nil },
            set: { if !$0 { workout.pendingStartConfirmation = nil } }
        )) {
            Button("Discard & Start", role: .destructive) {
                let action = workout.pendingStartConfirmation
                workout.pendingStartConfirmation = nil
                action?()
            }
            Button("Cancel", role: .cancel) { workout.pendingStartConfirmation = nil }
        } message: {
            Text("Starting a new ride will discard your held ride. This cannot be undone.")
        }
    }
}
