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
    @StateObject private var connectivity = ConnectivityManager.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?
    @State private var selectedRoute: Route?
    @State private var serviceRoutePickerService: IntegrationServiceID?

    @State private var selectedTab = 0
    @State private var navigationPath = NavigationPath()

    private var routeSections: [(DateSection, [Route])] {
        let sorted = routeStore.routes.sorted { $0.createdAt > $1.createdAt }
        return DateSection.group(sorted, by: \.createdAt)
    }

    var body: some View {
        TabView(selection: $selectedTab) {
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
                                                isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
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
                .onReceive(connectivity.$routeNamesOnWatch) { _ in uploadingRouteID = nil }
                .navigationDestination(for: Route.self) { route in
                    RouteDetailView(
                        route: route,
                        isOnWatch: connectivity.routeNamesOnWatch.contains(route.name),
                        isUploading: uploadingRouteID == route.id,
                        isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
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
            }
            .tabItem {
                Label("Routes", systemImage: "map")
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
                SettingsView(metricConfig: metricConfig, userSettings: userSettings, integrationSettings: integrationSettings)
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
            .tag(2)
        }
    }

    private func sendToWatch(_ route: Route) {
        guard uploadingRouteID == nil else { return }
        uploadingRouteID = route.id

        ConnectivityManager.shared.sendRoute(route) { result in
            DispatchQueue.main.async {
                if case .failure(let error) = result {
                    print("Failed to send route: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    uploadingRouteID = nil
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
