//
//  ContentView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/27/26.
//

import Combine
import SwiftUI
import UniformTypeIdentifiers
import WatchConnectivity

struct ContentView: View {
    @ObservedObject var routeStore: RouteStore
    @ObservedObject var rideStore: RideStore
    @ObservedObject var metricConfig: MetricConfigStore
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var integrationSettings: IntegrationSettingsStore
    @StateObject private var connectivity = ConnectivityManager.shared

    @ObservedObject private var importCoordinator = RouteImportCoordinator.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?
    /// Routes sent but not yet reported back by the watch. Several can wait at once.
    @State private var queuedRouteIDs: Set<UUID> = []
    @State private var isSelectingRoutes = false
    @State private var selectedRouteIDs: Set<UUID> = []
    @State private var showDeleteRoutesConfirm = false
    @State private var isExportingRoutes = false
    @State private var routeExport: GPXExportFile?
    @State private var showQueuedAlert = false
    @State private var selectedRoute: Route?
    @State private var serviceRoutePickerService: IntegrationServiceID?

    @StateObject private var rideSession = RideSessionManager.shared
    @Environment(\.scenePhase) private var scenePhase

    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()

    @AppStorage("hasSeenSettingsRec") private var hasSeenSettingsRec = false

    @AppStorage("autoSendRoutesToWatch") private var autoSendRoutesToWatch: Bool = false

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
                    RideControlView(
                        metricConfig: metricConfig, userSettings: userSettings,
                        routeStore: routeStore, rideStore: rideStore)
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
                .navigationTitle(
                    isSelectingRoutes ? "\(selectedRouteIDs.count) Selected" : "Routes"
                )
                .safeAreaInset(edge: .bottom) {
                    if isSelectingRoutes {
                        routeSelectionBar()
                    }
                }
                .sheet(item: $routeExport) { file in
                    ShareSheet(activityItems: [file.url])
                }
                .confirmationDialog(
                    "Delete \(selectedRouteIDs.count) \(selectedRouteIDs.count == 1 ? "route" : "routes")?",
                    isPresented: $showDeleteRoutesConfirm,
                    titleVisibility: .visible
                ) {
                    Button("Delete", role: .destructive) {
                        routeStore.routes.filter { selectedRouteIDs.contains($0.id) }.forEach(
                            routeStore.delete)
                        exitRouteSelection()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Removes them from this phone. Copies already on the watch stay there.")
                }
                .onAppear {
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                }
                .onReceive(connectivity.$routeIDsOnWatch) { ids in
                    if let id = uploadingRouteID, ids.contains(id) { uploadingRouteID = nil }
                    queuedRouteIDs.subtract(ids)
                }
                .onReceive(NotificationCenter.default.publisher(for: .watchTransferQueueChanged)) {
                    _ in
                    // A route whose transfer was cancelled isn't queued anymore.
                    queuedRouteIDs.formIntersection(connectivity.queuedRouteTransferIDs)
                }
                .navigationDestination(for: Route.self) { route in
                    RouteDetailView(
                        route: route,
                        isOnWatch: connectivity.routeIDsOnWatch.contains(route.id),
                        isUploading: uploadingRouteID == route.id,
                        isQueued: queuedRouteIDs.contains(route.id),
                        isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
                        canSendToWatch: canSendToWatch,
                        onSend: { sendToWatch(route) },
                        routeStore: routeStore
                    )
                }
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) {
                        if !isSelectingRoutes {
                            ConnectionStatusButton(
                                connectivity: connectivity,
                                routeStore: routeStore
                            )
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if isSelectingRoutes {
                            Button("Cancel") { exitRouteSelection() }
                        } else if !routeStore.routes.isEmpty {
                            Button("Select") {
                                withAnimation { isSelectingRoutes = true }
                            }
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        if !isSelectingRoutes {
                            Menu {
                                Button {
                                    showFilePicker = true
                                } label: {
                                    Label("From Files", systemImage: "folder")
                                }
                                ForEach(integrationSettings.settings.importRouteServices) {
                                    service in
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

                                Divider()

                                Toggle("Auto-Send to Watch", isOn: $autoSendRoutesToWatch)
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
                .alert(
                    "Import Error",
                    isPresented: .init(
                        get: { importError != nil },
                        set: { if !$0 { importError = nil } }
                    )
                ) {
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
                Label(
                    "Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath.fill")
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
                SettingsView(
                    metricConfig: metricConfig, userSettings: userSettings,
                    integrationSettings: integrationSettings, rideStore: rideStore,
                    routeStore: routeStore)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
        .layoutProbe("Root", corner: .topTrailing)
        .alert("Route Not Reaching Your Watch", isPresented: $connectivity.routeTransferStalled) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(
                "Your watch is connected, but the route hasn't started sending. Restarting your Apple Watch and then your iPhone usually clears this up. Send the route again if it hasn't shown up after they reconnect."
            )
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
    }

    /// If a LiveActivityIntent or live-activity deep link requested a tab
    /// switch, honor it once.
    private func consumePendingNavigation() {
        let defaults = UserDefaults(suiteName: "group.com.aidan3445.computa")
        guard let dest = defaults?.string(forKey: "pendingAppNavigation"), !dest.isEmpty else {
            return
        }
        defaults?.removeObject(forKey: "pendingAppNavigation")
        switch dest {
        case "ride":
            // Dynamic Ride tab only exists while a ride is active. If it
            // isn't, fall through to the rides list.
            if rideSession.isRideActive {
                selectedTab = 3
            } else {
                selectedTab = 1
            }
        case "rides":
            selectedTab = 1
        default:
            break
        }
    }

    private func sendToWatch(_ route: Route) {
        guard uploadingRouteID == nil else { return }
        uploadingRouteID = route.id
        queuedRouteIDs.remove(route.id)

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
                    queuedRouteIDs.insert(route.id)
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
            HStack(spacing: 8) {
                RouteRow(
                    route: route,
                    isOnWatch: connectivity.routeIDsOnWatch.contains(route.id),
                    isUploading: uploadingRouteID == route.id,
                    isQueued: queuedRouteIDs.contains(route.id),
                    isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
                    canSendToWatch: canSendToWatch,
                    onSend: { sendToWatch(route) },
                    onRename: { newName in
                        routeStore.rename(route, to: newName)
                    }
                )
                .frame(maxWidth: .infinity, alignment: .leading)
                // Same row as outside Select, so nothing shifts, but taps
                // select instead of hitting the send button.
                .allowsHitTesting(!isSelectingRoutes)
                RowTrailingSlot(isSelecting: isSelectingRoutes, showsChevron: true) {
                    Image(systemName: selectedRouteIDs.contains(route.id) ? "checkmark.circle.fill" : "circle")
                        .font(.title3)
                        .foregroundStyle(selectedRouteIDs.contains(route.id) ? Color.accentColor : .secondary)
                }
            }
            .contentShape(Rectangle())
            .background {
                if !isSelectingRoutes {
                    NavigationLink(value: route) { EmptyView() }
                        .opacity(0)
                }
            }
            // Only claims taps in Select mode, so outside it the row opens.
            .gesture(TapGesture().onEnded {
                if selectedRouteIDs.contains(route.id) {
                    selectedRouteIDs.remove(route.id)
                } else {
                    selectedRouteIDs.insert(route.id)
                }
            }, including: isSelectingRoutes ? .all : .subviews)
        }
        .onDelete { indices in
            guard !isSelectingRoutes else { return }
            deleteRoutes(at: indices, from: routes)
        }
    }

    func routeSelectionBar() -> some View {
        HStack(spacing: 8) {
            Button {
                exportSelectedRoutes()
            } label: {
                Label {
                    Text(selectedRouteIDs.count > 1 ? "Export GPX ZIP" : "Export GPX")
                } icon: {
                    if isExportingRoutes {
                        ProgressView()
                    } else {
                        Image(systemName: "square.and.arrow.up")
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedRouteIDs.isEmpty || isExportingRoutes)

            Button(role: .destructive) {
                showDeleteRoutesConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedRouteIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    /// One route exports as a plain GPX, several as a zip.
    func exportSelectedRoutes() {
        let routes = routeStore.routes.filter { selectedRouteIDs.contains($0.id) }
        guard !routes.isEmpty else { return }
        isExportingRoutes = true
        Task.detached(priority: .userInitiated) {
            let url =
                routes.count == 1
                ? RouteStore.exportGPXFile(for: routes[0])
                : RouteStore.exportZipGPX(routes: routes)
            await MainActor.run {
                isExportingRoutes = false
                routeExport = url.map(GPXExportFile.init)
            }
        }
    }

    func exitRouteSelection() {
        withAnimation {
            isSelectingRoutes = false
            selectedRouteIDs.removeAll()
        }
    }

    func deleteRoutes(at offsets: IndexSet, from routes: [Route]) {
        let toDelete = offsets.map { routes[$0] }
        toDelete.forEach(routeStore.delete)
    }
}
