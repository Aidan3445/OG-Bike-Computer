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

    @ObservedObject private var importCoordinator = RouteImportCoordinator.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?
    @State private var queuedRouteID: UUID?
    @State private var showQueuedAlert = false
    @State private var selectedRoute: Route?
    @State private var serviceRoutePickerService: IntegrationServiceID?

    @StateObject private var rideSession = RideSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()
    
    @AppStorage("hasSeenSettingsRec") private var hasSeenSettingsRec = false
    
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
                    RideControlView(metricConfig: metricConfig, userSettings: userSettings, routeStore: routeStore)
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
                                    routeList(routes: routes)
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
                RideHistoryView(rideStore: rideStore, routeStore: routeStore)
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
        .sheet(isPresented: $importCoordinator.showActionSheet) {
            RouteImportActionSheet()
        }
        .sheet(isPresented: .constant(!hasSeenSettingsRec)) {
            SettingsRecommendationView {
                hasSeenSettingsRec = true
            }
        }
        .onAppear { consumePendingNavigation() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { consumePendingNavigation() }
        }
        .fullScreenCover(isPresented: $showRideControlFullScreen) {
            NavigationStack {
                RideControlView(metricConfig: metricConfig, userSettings: userSettings, routeStore: routeStore)
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

    /// If a LiveActivityIntent requested a tab switch, honor it once.
    private func consumePendingNavigation() {
        let defaults = UserDefaults(suiteName: "group.com.aidan3445.computa")
        guard let dest = defaults?.string(forKey: "pendingAppNavigation"), !dest.isEmpty else { return }
        defaults?.removeObject(forKey: "pendingAppNavigation")
        switch dest {
        case "rides":
            showRideControlFullScreen = false
            selectedTab = 1
        default:
            break
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
            var allImported: [Route] = []
            for url in urls {
                guard url.startAccessingSecurityScopedResource() else { continue }
                defer { url.stopAccessingSecurityScopedResource() }

                guard let data = try? Data(contentsOf: url) else {
                    importError = "Could not read file: \(url.lastPathComponent)"
                    continue
                }

                let routes = RouteImportPipeline.shared.importGPX(data: data)
                if routes.isEmpty {
                    importError = "No routes found in \(url.lastPathComponent)"
                } else {
                    allImported.append(contentsOf: routes)
                }
            }
            if !allImported.isEmpty {
                RouteImportCoordinator.shared.handle(allImported)
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}

extension ContentView {
    @ViewBuilder
    func routeList(routes: [Route]) -> some View {
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
            deleteRoutes(at: indices, from: routes)
        }
    }

    func deleteRoutes(at offsets: IndexSet, from routes: [Route]) {
        let toDelete = offsets.map { routes[$0] }
        toDelete.forEach(routeStore.delete)
    }
}
