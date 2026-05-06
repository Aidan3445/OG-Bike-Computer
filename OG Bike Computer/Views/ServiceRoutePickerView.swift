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
    @State private var showImportSheet = false

    // Import by URL
    @State private var importURL = ""
    @State private var importedRoute: ServiceRoute?
    @State private var isResolvingURL = false
    @State private var urlError: String?

    // RWGPS only
    @State private var collections: [RWGPSCollection] = []
    // filters
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
    
    private var showError: Binding<Bool> {
        Binding<Bool>(
            get: { error != nil },
            set: { if !$0 { error = nil } }
        )
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
                        
                        if !routes.isEmpty {
                            serviceRoutesSection
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
            .searchable(text: $searchText, prompt: "Search your routes")
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
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        showImportSheet = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showFilters) {
                distanceFilterSheet
            }
            .sheet(isPresented: $showImportSheet) {
                importByUrlSheet
            }
            .alert("Error", isPresented: showError) {
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
            Text("Only public routes you have created, saved, or duplicated appear here. To import a private route, set it to public on Strava first.")
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
    
    // MARK: - Import by URL

    private var importByUrlSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("https://...", text: $importURL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .onSubmit { resolveImportURL() }
                        .onChange(of: importURL) {
                            importedRoute = nil
                            urlError = nil
                        }
                } header: {
                    Text("Route URL")
                }

                if isResolvingURL {
                    HStack {
                        Spacer()
                        ProgressView()
                        Spacer()
                    }
                } else if let route = importedRoute {
                    Section {
                        Button {
                            downloadRoute(route)
                        } label: {
                            ServiceRouteRow(route: route, isDownloading: downloadingID == route.id)
                        }
                        .disabled(downloadingID != nil)
                    } header: {
                        Text("Route Preview")
                    }
                } else if let err = urlError {
                    Section {
                        Text(err)
                            .foregroundStyle(.red)
                            .font(.footnote)
                    }
                }
            }
            .navigationTitle("Import by URL")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showImportSheet = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Find") { resolveImportURL() }
                        .disabled(importURL.isEmpty || isResolvingURL)
                        .fontWeight(.semibold)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func resolveImportURL() {
        importedRoute = nil
        urlError = nil
        isResolvingURL = true

        Task {
            do {
                let route: ServiceRoute
                if service == .rideWithGPS {
                    let rwgps = RWGPSClient()
                    guard let id = rwgps.extractRouteID(from: importURL) else {
                        throw ServiceError.invalidURL
                    }
                    route = try await rwgps.fetchRouteMetadata(id: id)
                } else {
                    let strava = StravaClient()
                    guard let id = strava.extractRouteID(from: importURL) else {
                        throw ServiceError.invalidURL
                    }
                    route = try await strava.fetchRouteMetadata(id: id)
                }
                await MainActor.run {
                    importedRoute = route
                    isResolvingURL = false
                }
            } catch {
                await MainActor.run {
                    urlError = error.localizedDescription
                    isResolvingURL = false
                }
            }
        }
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
            // Pinned is always returned last but we want it first.
            // Reorder and limit to 4 items total before showing "View All" option
            let items = Array(collections.suffix(1)) + Array(collections.prefix(collections.count - 1).prefix(3))

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
    
    @ViewBuilder
    private var serviceRoutesSection: some View {
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
            .foregroundStyle(.primary.opacity(0.8))
        }
        .padding(.vertical, 2)
    }
}
