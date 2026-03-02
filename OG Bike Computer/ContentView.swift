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
    @StateObject private var connectivity = ConnectivityManager.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if routeStore.routes.isEmpty {
                        ContentUnavailableView(
                            "No Routes",
                            systemImage: "map",
                            description: Text("Import a GPX file to get started."))
                    } else {
                        List {
                            ForEach(routeStore.routes) { route in
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
                            .onDelete { indices in
                                for i in indices {
                                    routeStore.delete(routeStore.routes[i])
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Computa")
                .onAppear { ConnectivityManager.shared.attachStores(rideStore: rideStore) }
                .onReceive(connectivity.$routeNamesOnWatch) { _ in uploadingRouteID = nil }
                .toolbar {
                    Button {
                        showFilePicker = true
                    } label: {
                        Label("Import GPX", systemImage: "plus")
                    }
                }
                .fileImporter(
                    isPresented: $showFilePicker,
                    allowedContentTypes: [.gpx, .xml, .data],
                    allowsMultipleSelection: true
                ) { result in
                    handleImport(result)
                }
                .alert("Import Error", isPresented: .init(
                    get: { importError != nil },
                    set: { if !$0 { importError = nil } }
                )) {
                    Button("OK") { importError = nil }
                } message: {
                    Text(importError ?? "")
                }

                ConnectionStatusBar(connectivity: connectivity, routeStore: routeStore)
            }
        }
    }

    private func sendToWatch(_ route: Route) {
        print(String(format: "85 sendToWatch() %@", uploadingRouteID?.uuidString ?? "nil"))
        guard uploadingRouteID == nil else { return }
        uploadingRouteID = route.id
        print(String(format: "88 sendToWatch() %@", uploadingRouteID?.uuidString ?? "nil"))

        ConnectivityManager.shared.sendRoute(route) { result in
            DispatchQueue.main.async {
                print(String(format: "92 sendToWatch()"))
                if case .failure(let error) = result {
                    print("Failed to send route: \(error)")
                }
                DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
                    uploadingRouteID = nil
                    print(String(format: "98 sendToWatch() %@", uploadingRouteID?.uuidString ?? "nil"))
                }
            }
        }
    }

    private func handleImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
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
