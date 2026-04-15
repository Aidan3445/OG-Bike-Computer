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
    @State private var currentPage = 1
    @State private var hasMore = true
    @State private var error: String?
    @State private var downloadingID: String?

    // RWGPS only
    @State private var collections: [RWGPSCollection] = []
    // RWGPS filters
    @State private var searchText = ""
    @State private var showFilters = false
    @State private var distanceMin: String = ""
    @State private var distanceMax: String = ""
    @State private var activeFilter = RWGPSRouteFilter()

    @ObservedObject private var unitState = UnitState.shared

    private var rwgpsClient: RWGPSClient? {
        service == .rideWithGPS ? RWGPSClient() : nil
    }

    private var client: ServiceClient {
        if let rwgps = rwgpsClient {
            return rwgps
        }
        return StravaClient()
    }

    private var isImperial: Bool {
        unitState.preferences.distance == .miles
    }

    private var distanceUnitLabel: String {
        isImperial ? "mi" : "km"
    }

    var body: some View {
        NavigationStack {
            Group {
                if routes.isEmpty && isLoading {
                    ProgressView("Loading routes...")
                } else if routes.isEmpty && !isLoading {
                    VStack(spacing: 16) {
                        ContentUnavailableView(
                            "No Routes Found",
                            systemImage: "map",
                            description: Text(activeFilter.isEmpty
                                ? "No routes found on your \(service.displayName) account."
                                : "No routes match your filters. Try adjusting your search."))
                        if service == .strava {
                            stravaVisibilityNote
                        }
                    }
                } else {
                    List {
                        if service == .rideWithGPS && !collections.isEmpty {
                            collectionsSection
                        }

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
                            Text("Your Routes")
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

                        if service == .strava {
                            Section {
                                stravaVisibilityNote
                            }
                        }
                    }
                }
            }
            .navigationTitle("From \(service.displayName)")
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $searchText, prompt: "Search routes")
            .onSubmit(of: .search) {
                applyFilters()
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if service == .rideWithGPS {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            showFilters.toggle()
                        } label: {
                            Image(systemName: activeFilter.isEmpty && searchText.isEmpty
                                  ? "line.3.horizontal.decrease.circle"
                                  : "line.3.horizontal.decrease.circle.fill")
                        }
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                distanceFilterSheet
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
                await fetchCollections()
                await fetchRoutes()
            }
        }
    }

    private var stravaVisibilityNote: some View {
        Label {
            Text("Only public routes appear here. To import a private route, set it to public on Strava first.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } icon: {
            Image(systemName: "eye.slash")
                .foregroundStyle(.secondary)
        }
    }

    // MARK: - Distance Filter Sheet

    private var distanceFilterSheet: some View {
        NavigationStack {
            Form {
                Section {
                    HStack {
                        Text("Min")
                            .foregroundStyle(.secondary)
                        TextField("0", text: $distanceMin)
                            .keyboardType(.decimalPad)
                        Text(distanceUnitLabel)
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Max")
                            .foregroundStyle(.secondary)
                        TextField("Any", text: $distanceMax)
                            .keyboardType(.decimalPad)
                        Text(distanceUnitLabel)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Distance Range")
                }

                if !activeFilter.isEmpty || !searchText.isEmpty {
                    Section {
                        Button("Clear All Filters", role: .destructive) {
                            searchText = ""
                            distanceMin = ""
                            distanceMax = ""
                            showFilters = false
                            applyFilters()
                        }
                    }
                }
            }
            .navigationTitle("Filters")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showFilters = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Apply") {
                        showFilters = false
                        applyFilters()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Filter Logic

    private func applyFilters() {
        var filter = RWGPSRouteFilter()
        filter.name = searchText

        // Convert user-entered distance to meters
        if let minVal = Double(distanceMin), minVal > 0 {
            let meters = isImperial ? minVal * 1609.344 : minVal * 1000
            filter.distanceMin = Int(meters)
        }
        if let maxVal = Double(distanceMax), maxVal > 0 {
            let meters = isImperial ? maxVal * 1609.344 : maxVal * 1000
            filter.distanceMax = Int(meters)
        }

        activeFilter = filter

        // Reset and re-fetch
        routes = []
        currentPage = 1
        hasMore = true
        Task { await fetchRoutes() }
    }

    // MARK: - Data

    private func fetchRoutes() async {
        isLoading = true
        do {
            let serviceClient: ServiceClient
            if service == .rideWithGPS {
                let rwgps = RWGPSClient()
                rwgps.filter = activeFilter
                serviceClient = rwgps
            } else {
                serviceClient = StravaClient()
            }

            let fetched = try await serviceClient.fetchRoutes(page: currentPage)
            routes.append(contentsOf: fetched)
            hasMore = fetched.count >= 20
        } catch {
            self.error = error.localizedDescription
        }
        isLoading = false
    }

    private func fetchCollections() async {
        guard let rwgps = rwgpsClient else { return }
        do {
            collections = try await rwgps.fetchCollections()
        } catch {
            // Silently ignore collection loading errors since they're not critical
            print("Failed to load RWGPS collections: \(error)")
        }
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

    @ViewBuilder
    private var collectionsSection: some View {
        Section {
            let items = Array(collections.prefix(4))

            ForEach(items) { collection in
                NavigationLink(destination: RWGPSCollectionView(
                    collections: collections,
                    selectedCollection: collection,
                    routeStore: routeStore
                )) {
                    Text(collection.name)
                }
            }
            if collections.count > 4 {
                NavigationLink(destination: RWGPSCollectionView(
                    collections: collections,
                    selectedCollection: nil,
                    routeStore: routeStore
                )) {
                    Text("View All (+\(collections.count - 4))")
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Collections")
        }
    }
}

struct ServiceRouteRow: View {
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
            .foregroundStyle(.primary)
            .foregroundStyle(.opacity(80))
        }
        .padding(.vertical, 2)
    }
}
