//
//  RouteImportActionSheet.swift
//  OG Bike Computer
//
//  Instagram-style "what do you want to do with this route?" sheet.
//  Shown whenever a GPX file is received from the Share Sheet, file picker,
//  or a deep-link URL.  AppIntents that know the destination skip this sheet.
//

import SwiftUI

struct RouteImportActionSheet: View {
    @ObservedObject private var coordinator  = RouteImportCoordinator.shared
    @ObservedObject private var rideSession  = RideSessionManager.shared
    @ObservedObject private var connectivity = ConnectivityManager.shared

    private var canSendToWatch: Bool {
        connectivity.isPaired && connectivity.isWatchAppInstalled
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(coordinator.pendingRoutes) { route in
                    Section {
                        // ── Save only ──────────────────────────────────────
                        Button {
                            coordinator.clear()
                        } label: {
                            Label("Save to Phone", systemImage: "iphone")
                        }

                        // ── Watch actions (only shown when watch is available) ──
                        if canSendToWatch {
                            if rideSession.isRideActive {
                                // Mid-ride: offer a route switch instead
                                Button {
                                    sendToWatch(route, pendingAction: "changeRoute")
                                } label: {
                                    Label("Switch to This Route", systemImage: "arrow.triangle.swap")
                                }
                            } else {
                                Button {
                                    sendToWatch(route, pendingAction: nil)
                                } label: {
                                    Label("Send to Watch", systemImage: "applewatch")
                                }

                                Button {
                                    sendToWatch(route, pendingAction: "startRide")
                                } label: {
                                    Label("Send + Start Ride", systemImage: "figure.outdoor.cycle")
                                }
                            }
                        }
                    } header: {
                        Text(route.name)
                            .font(.headline)
                            .textCase(nil)
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle(
                coordinator.pendingRoutes.count == 1
                    ? "Route Imported"
                    : "\(coordinator.pendingRoutes.count) Routes Imported"
            )
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Done") { coordinator.clear() }
                }
            }
        }
    }

    // MARK: Helpers

    private func sendToWatch(_ route: Route, pendingAction: String?) {
        ConnectivityManager.shared.sendRoute(
            route,
            pendingAction: pendingAction,
            activityType: pendingAction == "startRide" ? "cycling" : nil
        ) { _ in }
        coordinator.clear()
    }
}
