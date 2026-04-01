//
//  ServiceRoutePickerView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI

struct ServiceRoutePickerView: View {
    let service: IntegrationServiceID
    let routeStore: RouteStore
    @Environment(\.dismiss) private var dismiss

    @State private var routes: [ServiceRoute] = []
    @State private var isLoading = false
    @State private var currentPage = 0
    @State private var hasMore = true
    @State private var error: String?
    @State private var downloadingID: String?

    private var client: ServiceClient {
        switch service {
        case .rideWithGPS: return RWGPSClient()
        case .strava: return StravaClient()
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty && isLoading {
                    ProgressView("Loading routes...")
                } else if routes.isEmpty && !isLoading {
                    ContentUnavailableView(
                        "No Routes Found",
                        systemImage: "map",
                        description: Text("No routes found on your \(service.displayName) account."))
                } else {
                    List {
                        ForEach(routes) { route in
                            Button {
                                downloadRoute(route)
                            } label: {
                                ServiceRouteRow(
                                    route: route,
                                    isDownloading: downloadingID == route.id
                                )
                            }
                            .disabled(downloadingID != nil)
                        }

                        if hasMore {
                            Button {
                                loadMore()
                            } label: {
                                HStack {
                                    Spacer()
                                    if isLoading {
                                        ProgressView()
                                    } else {
                                        Text("Load More")
                                    }
                                    Spacer()
                                }
                            }
                            .disabled(isLoading)
                        }
                    }
                }
            }
            .navigationTitle("From \(service.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .alert("Error", isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )) {
                Button("OK") { error = nil }
            } message: {
                Text(error ?? "")
            }
            .task {
                await fetchRoutes()
            }
        }
    }

    private func fetchRoutes() async {
        isLoading = true
        do {
            let fetched = try await client.fetchRoutes(page: currentPage)
            routes.append(contentsOf: fetched)
            hasMore = fetched.count >= 20
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func loadMore() {
        currentPage += 1
        Task { await fetchRoutes() }
    }

    private func downloadRoute(_ serviceRoute: ServiceRoute) {
        downloadingID = serviceRoute.id
        Task {
            do {
                let route = try await client.downloadRoute(id: serviceRoute.id)
                await MainActor.run {
                    routeStore.save(route)
                    dismiss()
                }
            } catch {
                await MainActor.run {
                    self.error = error.localizedDescription
                    downloadingID = nil
                }
            }
        }
    }
}

private struct ServiceRouteRow: View {
    let route: ServiceRoute
    let isDownloading: Bool
    @ObservedObject private var unitState = UnitState.shared

    var body: some View {
        let _ = unitState.preferences
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(route.name)
                    .font(.headline)
                    .foregroundStyle(.primary)
                Spacer()
                if isDownloading {
                    ProgressView()
                }
            }
            HStack(spacing: 12) {
                Label(formatDistance(route.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if route.elevationGain > 0 {
                    Label(formatElevation(route.elevationGain), systemImage: "arrow.up.right")
                }
            }
            .labelStyle(StatLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
