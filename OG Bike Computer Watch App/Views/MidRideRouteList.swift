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
    @ObservedObject private var unitState = UnitState.shared

    // Shown right away while loadRoute processes the route off the main thread.
    @State private var pendingRoute: Route?

    var body: some View {
        let _ = unitState.preferences
        List {
            Section {
                if let pendingRoute {
                    HStack {
                        ProgressView()
                            .frame(width: 20, height: 20)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(pendingRoute.name)
                                .font(.headline)
                                .fixedSize(horizontal: false, vertical: true)
                            Text("Loading route")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                } else if workout.hasRoute {
                    let name = workout.navigation.processedRoute?.name ?? "Route"
                    HStack {
                        Image(systemName: "location.fill")
                            .foregroundStyle(.green)
                        Text(name)
                            .font(.headline)
                            .fixedSize(horizontal: false, vertical: true)
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
                if workout.hasRoute && pendingRoute == nil {
                    Button {
                        workout.clearRoute()
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "bicycle")
                            Text("Free Ride")
                        }
                        .font(.subheadline)
                    }
                }
                if store.routes.isEmpty {
                    Text("No routes available")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(store.routes) { route in
                        let isPending = pendingRoute?.id == route.id
                        let isActive = pendingRoute == nil && workout.navigation.processedRoute?.name == route.name
                        Button {
                            if !isActive { swapRoute(route) }
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(route.name)
                                        .font(.subheadline)
                                    Text(formatDistance(route.distance))
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if isPending {
                                    ProgressView()
                                        .frame(width: 20, height: 20)
                                } else if isActive {
                                    Image(systemName: "checkmark.circle.fill")
                                        .foregroundStyle(.green)
                                }
                            }
                        }
                        .disabled(isActive || pendingRoute != nil)
                    }
                }
            } header: {
                Text("Switch Route")
                    .font(.caption2)
            }
        }
        .navigationTitle("Routes")
    }

    private func swapRoute(_ route: Route) {
        pendingRoute = route
        DispatchQueue.global(qos: .userInitiated).async {
            workout.loadRoute(route)
            DispatchQueue.main.async {
                pendingRoute = nil
                VoiceNavigator.shared.resetForRouteSwap()
            }
        }
    }
}
