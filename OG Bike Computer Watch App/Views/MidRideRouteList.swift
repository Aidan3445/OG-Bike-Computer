//
//  MidRideRouteList.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/15/26.
//

import SwiftUI

struct MidRideRouteList: View {
    @ObservedObject var store: RouteStore
    @ObservedObject var workout: WorkoutManager

    @State private var swapping: Route?
    @State private var showConfirm = false

    var body: some View {
        List {
            Section {
                if workout.hasRoute {
                    let name = workout.navigation.processedRoute?.name ?? "Route"
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.green)
                        Text(name)
                            .font(.headline)
                            .lineLimit(1)
                    }
                } else {
                    HStack {
                        Image(systemName: "record.circle")
                            .foregroundStyle(.orange)
                        Text("Free Ride")
                            .font(.headline)
                    }
                }
            } header: {
                Text("Active")
                    .font(.caption2)
            }

            Section {
                if store.routes.isEmpty {
                    Text("No routes available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.routes) { route in
                        let isActive = workout.navigation.processedRoute?.name == route.name

                        Button {
                            if !isActive {
                                swapping = route
                                showConfirm = true
                            }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                        .font(.subheadline)
                                        .lineLimit(1)
                                    Text(formatDistance(route.distance))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(isActive)
                    }
                }
            } header: {
                Text("Switch Route")
                    .font(.caption2)
            }
        }
        .navigationTitle("Routes")
        .alert("Switch Route?", isPresented: $showConfirm) {
            Button("Switch") {
                if let route = swapping {
                    swapRoute(route)
                }
                swapping = nil
            }
            Button("Cancel", role: .cancel) {
                swapping = nil
            }
        } message: {
            if let route = swapping {
                Text("Switch navigation to \(route.name)? Your ride recording continues uninterrupted.")
            }
        }
    }

    private func swapRoute(_ route: Route) {
        // Process on background thread — can take a moment
        DispatchQueue.global(qos: .userInitiated).async {
            workout.loadRoute(route)
            DispatchQueue.main.async {
                // Reset voice nav state for the new route
                VoiceNavigator.shared.resetForRouteSwap()
            }
        }
    }
}
