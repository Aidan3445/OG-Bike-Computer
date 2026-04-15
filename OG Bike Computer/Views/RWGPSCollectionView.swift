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

    @Environment(\.dismiss) private var dismiss

    @State private var routes: [ServiceRoute] = []
    @State private var isLoading = false
    @State private var error: String?
    @State private var downloadingID: String?

    var body: some View {
        Group {
            if let collection = selectedCollection {
                collectionRoutesView(collection: collection)
            } else {
                collectionsListView
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
    }

    // MARK: - No Collection Selected

    private var collectionsListView: some View {
        List {
            ForEach(collections) { collection in
                NavigationLink(destination: RWGPSCollectionView(
                    collections: collections,
                    selectedCollection: collection,
                    routeStore: routeStore
                )) {
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
                                downloadRoute(route)
                            } label: {
                                ServiceRouteRow(
                                    route: route,
                                    isDownloading: downloadingID == route.id
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

    private func downloadRoute(_ serviceRoute: ServiceRoute) {
        downloadingID = serviceRoute.id
        Task {
            do {
                let route = try await RWGPSClient().downloadRoute(id: serviceRoute.id)
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
