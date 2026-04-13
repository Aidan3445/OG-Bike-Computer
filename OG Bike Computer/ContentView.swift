//
//  ContentView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI
import UniformTypeIdentifiers
import WatchConnectivity
import Combine

struct ContentView: View {
    @ObservedObject var routeStore: RouteStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var integrationSettings: IntegrationSettingsStore
    @Binding var showRideControlFullScreen: Bool
    @StateObject private var connectivity = ConnectivityManager.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?
    @State private var queuedRouteID: UUID?
    @State private var showQueuedAlert = false
    @State private var selectedRoute: Route?
    @State private var serviceRoutePickerService: IntegrationServiceID?

    @StateObject private var rideSession = RideSessionManager.shared

    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()

    /// Whether the watch is paired and has the app installed
    private var canSendToWatch: Bool {
        connectivity.isPaired && connectivity.isWatchAppInstalled
    }

    private var routeSections: [(DateSection, [Route])] {
        let sorted = routeStore.routes.sorted { $0.createdAt > $1.createdAt }
        return DateSection.group(sorted, by: \.createdAt)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            // Dynamic Ride tab — appears only during active rides
            if rideSession.isRideActive {
                NavigationStack {
                    RideControlView(metricConfig: metricConfig, userSettings: userSettings)
                }
                .tabItem {
                    Label("Ride", systemImage: "helmet.fill")
                }
                .tag(3)
            }
            
            NavigationStack(path: $navigationPath) {
                Group {
                    if routeStore.routes.isEmpty {
                        ContentUnavailableView(
                            "No Routes",
                            systemImage: "map",
                            description: Text("Import a GPX file to get started."))
                    } else {
                        List {
                            ForEach(routeSections, id: \.0) { section, routes in
                                Section {
                                    ForEach(routes) { route in
                                        NavigationLink(value: route) {
                                            RouteRow(
                                                route: route,
                                                isOnWatch: connectivity.routeNamesOnWatch.contains(route.name),
                                                isUploading: uploadingRouteID == route.id,
                                                isQueued: queuedRouteID == route.id,
                                                isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
                                                canSendToWatch: canSendToWatch,
                                                onSend: { sendToWatch(route) },
                                                onRename: { newName in
                                                    routeStore.rename(route, to: newName)
                                                }
                                            )
                                        }
                                    }
                                    .onDelete { indices in
                                        for i in indices {
                                            routeStore.delete(routes[i])
                                        }
                                    }
                                } header: {
                                    Text(section.title)
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Routes")
                .onAppear {
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                    routeStore.onImport = { route in
                        selectedTab = 0
                        navigationPath.append(route)
                    }
                }
                .onReceive(connectivity.$routeNamesOnWatch) { _ in
                    uploadingRouteID = nil
                    queuedRouteID = nil
                }
                .navigationDestination(for: Route.self) { route in
                    RouteDetailView(
                        route: route,
                        isOnWatch: connectivity.routeNamesOnWatch.contains(route.name),
                        isUploading: uploadingRouteID == route.id,
                        isQueued: queuedRouteID == route.id,
                        isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
                        canSendToWatch: canSendToWatch,
                        onSend: { sendToWatch(route) }
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        ConnectionStatusButton(
                            connectivity: connectivity,
                            routeStore: routeStore
                        )
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if integrationSettings.settings.importRouteServices.isEmpty {
                            Button {
                                showFilePicker = true
                            } label: {
                                Label("Import GPX", systemImage: "plus")
                            }
                        } else {
                            Menu {
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("From Files", systemImage: "folder")
                                }
                                ForEach(integrationSettings.settings.importRouteServices) { service in
                                    Button {
                                        serviceRoutePickerService = service
                                    } label: {
                                        Label {
                                            Text("From \(service.displayName)")
                                        } icon: {
                                            Image(service.iconAsset)
                                                .resizable()
                                                .scaledToFit()
                                        }
                                    }
                                }
                            } label: {
                                Label("Import", systemImage: "plus")
                            }
                        }
                    }
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.gpx, .xml, .data],
                    allowsMultipleSelection: true
                ) { result in
                    handleImport(result)
                }
                .sheet(item: $serviceRoutePickerService) { service in
                    ServiceRoutePickerView(service: service, routeStore: routeStore)
                }
                .alert("Import Error", isPresented: .init(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button("OK") { importError = nil }
                } message: {
                    Text(importError ?? "")
                }
                .alert("Route Queued", isPresented: $showQueuedAlert) {
                    Button("OK") {}
                } message: {
                    Text("The route will appear on your watch when you open the app.")
                }
            }
            .tabItem {
                Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
            }
            .tag(0)

            NavigationStack {
                RideHistoryView(rideStore: rideStore)
            }
            .tabItem {
                Label("Rides", systemImage: "bicycle")
            }
            .tag(1)

            NavigationStack {
                SettingsView(metricConfig: metricConfig, userSettings: userSettings, integrationSettings: integrationSettings, rideStore: rideStore, routeStore: routeStore)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .fullScreenCover(isPresented: $showRideControlFullScreen) {
            NavigationStack {
                RideControlView(metricConfig: metricConfig, userSettings: userSettings)
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Done") {
                                showRideControlFullScreen = false
                            }
                        }
                    }
            }
        }
    }

    private func sendToWatch(_ route: Route) {
        guard uploadingRouteID == nil else { return }
        uploadingRouteID = route.id
        queuedRouteID = nil

        ConnectivityManager.shared.sendRoute(route) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("Failed to send route: \(error)")
                    uploadingRouteID = nil
                    return
                }
                // After 3 seconds, if still uploading (watch hasn't confirmed),
                // transition to "queued" state
                DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                    guard uploadingRouteID == route.id else { return }
                    uploadingRouteID = nil
                    queuedRouteID = route.id
                    showQueuedAlert = true
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            print(String(format: "Importing %d files", urls.count))
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else {
                    importError = "Could not read file: \(url.lastPathComponent)"
                    continue
                }

                let parser = GPXParser()
                let parsed = parser.parse(data: data)

                if parsed.isEmpty {
                    importError = "No routes found in \(url.lastPathComponent)"
                } else {
                    for route in parsed {
                        routeStore.save(route)
                    }
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
