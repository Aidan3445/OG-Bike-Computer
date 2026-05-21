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

    /// Per-route resolution. The sheet stays open after each action so the
    /// rider can verify the result and act on the remaining routes — only
    /// "Done" dismisses.
    private enum Resolution: Equatable {
        case savedToPhone
        case sentToWatch
        case sentAndStarted
        case switched
        case failed(String)
    }

    @State private var resolutions: [UUID: Resolution] = [:]

    private var canSendToWatch: Bool {
        connectivity.isPaired && connectivity.isWatchAppInstalled
    }

    var body: some View {
        NavigationView {
            List {
                ForEach(coordinator.pendingRoutes) { route in
                    Section {
                        if let resolution = resolutions[route.id] {
                            resolvedRow(for: resolution)
                        } else {
                            // ── Save only ──────────────────────────────────────
                            Button {
                                resolutions[route.id] = .savedToPhone
                            } label: {
                                Label("Save to Phone", systemImage: "iphone")
                            }

                            // ── Watch actions (only shown when watch is available) ──
                            if canSendToWatch {
                                if rideSession.isRideActive {
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
                    Button("Done") {
                        resolutions = [:]
                        coordinator.clear()
                    }
                }
            }
            .onAppear { applyAutoSent() }
            .onChange(of: coordinator.autoSentRouteIDs) { _, _ in applyAutoSent() }
        }
    }

    private func applyAutoSent() {
        for id in coordinator.autoSentRouteIDs where resolutions[id] == nil {
            resolutions[id] = .sentToWatch
        }
    }

    @ViewBuilder
    private func resolvedRow(for resolution: Resolution) -> some View {
        switch resolution {
        case .savedToPhone:
            Label("Saved to Phone", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .sentToWatch:
            Label("Sent to Watch", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .sentAndStarted:
            Label("Sent — Ride Started on Watch", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .switched:
            Label("Switched to This Route", systemImage: "checkmark.circle.fill")
                .foregroundStyle(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
        }
    }

    // MARK: Helpers

    private func sendToWatch(_ route: Route, pendingAction: String?) {
        ConnectivityManager.shared.sendRoute(
            route,
            pendingAction: pendingAction,
            activityType: pendingAction == "startRide" ? "cycling" : nil
        ) { result in
            DispatchQueue.main.async {
                switch result {
                case .success:
                    switch pendingAction {
                    case "startRide":   resolutions[route.id] = .sentAndStarted
                    case "changeRoute": resolutions[route.id] = .switched
                    default:            resolutions[route.id] = .sentToWatch
                    }
                case .failure:
                    resolutions[route.id] = .failed("Send failed — try again")
                }
            }
        }
    }
}
