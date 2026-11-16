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
    /// True while a screen is pushed, so ContentView can keep History out of reach.
    @Binding var isShowingDetail: Bool

    @State private var path: [Destination] = []
    @State private var showHeldRideAlert = false
    @State private var showDiscardConfirmation = false
    #if DEBUG
    @State private var showSimulator = false
    #endif

    private enum Destination: Hashable {
        case start(Route?)
    }

    var body: some View {
        let _ = unitState.preferences // register dependency so list re-renders on unit change
        NavigationStack(path: $path) {
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

                            NavigationLink(value: Destination.start(nil)) {
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

                        NavigationLink(value: Destination.start(nil)) {
                            Label("Free Ride", systemImage: "record.circle")
                                .foregroundStyle(.orange)
                        }

                        ForEach(store.routes) { route in
                            NavigationLink(value: Destination.start(route)) {
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
                        Button {
                            showSimulator = true
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
                }
            }
            .navigationDestination(for: Destination.self) { destination in
                switch destination {
                case .start(let route):
                    StartRideView(route: route, workout: workout, rideStore: rideStore)
                }
            }
        }
        #if DEBUG
        // A sheet, not a push, so its list isn't fighting the home page's
        // vertical paging for scroll.
        .sheet(isPresented: $showSimulator) {
            NavigationStack {
                SimulationView(store: store, workout: workout, simulator: simulator)
            }
        }
        #endif
        .onChange(of: path) { _, newPath in
            isShowingDetail = !newPath.isEmpty
        }
        // The path resets when a ride takes over the screen, so resync on return.
        .onAppear {
            isShowingDetail = !path.isEmpty
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
