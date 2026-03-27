//
//  RouteList.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct RouteList: View {
    @ObservedObject var store: RouteStore
    @ObservedObject var workout: WorkoutManager
    @ObservedObject var simulator: RideSimulator
    @ObservedObject private var unitState = UnitState.shared

    var body: some View {
        let _ = unitState.preferences // register dependency so list re-renders on unit change
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

                        Divider().padding(.vertical, 4)

                        NavigationLink {
                            StartRideView(route: nil, workout: workout)
                        } label: {
                            Label("Free Ride", systemImage: "record.circle")
                                .frame(maxWidth: .infinity)
                        }
                        .tint(.orange)
                    }
                    .padding()
                } else {
                    List {
                        NavigationLink {
                            StartRideView(route: nil, workout: workout)
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

                        NavigationLink {
                            SimulationView(store: store, workout: workout, simulator: simulator)
                        } label: {
                            Label("Simulate", systemImage: "play.circle")
                        }

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
                        StartRideView(route: route, workout: workout)
                    }
                }
            }
        }
    }
}
