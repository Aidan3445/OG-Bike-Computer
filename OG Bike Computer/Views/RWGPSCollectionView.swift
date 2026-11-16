//
//  RWGPSCollectionView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/15/26.
//

import SwiftUI

struct RWGPSCollectionView: View {
    let collections: [RWGPSCollection]
    let selectedCollection: RWGPSCollection?
    let routeStore: RouteStore

    @State private var routes: [ServiceRoute] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var downloadingID: String?
    @State private var importedIDs: Set<String> = []
    @State private var replacePrompt: ReplacePrompt?

    var body: some View {
        Group {
            if let collection = selectedCollection {
                collectionRoutesView(collection: collection)
            } else {
                collectionsListView
            }
        }
        .alert(
            "Error",
            isPresented: .init(
                get: { error != nil },
                set: { if !$0 { error = nil } }
            )
        ) {
            Button("OK") { error = nil }
        } message: {
            Text(error ?? "")
        }
    }

    // MARK: - No Collection Selected

    private var collectionsListView: some View {
        List {
            ForEach(collections) { collection in
                NavigationLink(
                    destination: RWGPSCollectionView(
                        collections: collections,
                        selectedCollection: collection,
                        routeStore: routeStore
                    )
                ) {
                    Text(collection.name)
                }
            }
        }
        .navigationTitle("Collections")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Collection Selected

    @ViewBuilder
    private func collectionRoutesView(collection: RWGPSCollection) -> some View {
        Group {
            if routes.isEmpty && isLoading {
                ProgressView("Loading routes...")
            } else if routes.isEmpty && !isLoading {
                ContentUnavailableView(
                    "No Routes",
                    systemImage: "map",
                    description: Text("This collection has no routes.")
                )
            } else {
                List {
                    Section {
                        ForEach(routes) { route in
                            Button {
                                importTapped(route)
                            } label: {
                                ServiceRouteRow(
                                    route: route,
                                    isDownloading: downloadingID == route.id,
                                    isImported: isImported(route)
                                )
                            }
                            .disabled(downloadingID != nil)
                        }
                    } header: {
                        Text(collection.name)
                    }
                }
            }
        }
        .navigationTitle(collection.name)
        .navigationBarTitleDisplayMode(.inline)
        .replaceImportedRouteAlert(
            $replacePrompt, serviceName: IntegrationServiceID.rideWithGPS.displayName
        ) { prompt in
            downloadRoute(prompt.serviceRoute, replacing: prompt.existing)
        }
        .task {
            await fetchCollectionRoutes(id: collection.id)
        }
    }

    // MARK: - Data

    private func fetchCollectionRoutes(id: String) async {
        isLoading = true
        do {
            routes = try await RWGPSClient().fetchRoutesForCollection(id: id)
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    /// A route already imported from this service asks before downloading
    /// again, since a second download replaces the saved copy.
    private func importTapped(_ serviceRoute: ServiceRoute) {
        if let existing = existingRoute(for: serviceRoute) {
            replacePrompt = ReplacePrompt(serviceRoute: serviceRoute, existing: existing)
        } else {
            downloadRoute(serviceRoute)
        }
    }

    private func existingRoute(for serviceRoute: ServiceRoute) -> Route? {
        let source = RouteSource(service: .rideWithGPS, remoteID: serviceRoute.id)
        return routeStore.routes.first { $0.source == source }
    }

    private func isImported(_ serviceRoute: ServiceRoute) -> Bool {
        importedIDs.contains(serviceRoute.id) || existingRoute(for: serviceRoute) != nil
    }

    private func downloadRoute(_ serviceRoute: ServiceRoute, replacing existing: Route? = nil) {
        downloadingID = serviceRoute.id
        Task {
            do {
                let route = try await RWGPSClient().downloadRoute(id: serviceRoute.id)
                await MainActor.run {
                    if let existing {
                        routeStore.replace(existing, with: route)
                    } else {
                        routeStore.save(route)
                        RouteImportCoordinator.shared.autoSendIfEnabled(route)
                    }
                    importedIDs.insert(serviceRoute.id)
                    downloadingID = nil
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
