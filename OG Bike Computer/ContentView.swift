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
    @StateObject private var store = RouteStore()
    @StateObject private var connectivity = ConnectivityManager.shared

    @State private var showFilePicker = false
    @State private var importError: String?
    @State private var uploadingRouteID: UUID?

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Group {
                    if store.routes.isEmpty {
                        ContentUnavailableView(
                            "No Routes",
                            systemImage: "map",
                            description: Text("Import a GPX file to get started."))
                    } else {
                        List {
                            ForEach(store.routes) { route in
                                RouteRow(
                                    route: route,
                                    isOnWatch: connectivity.routeNamesOnWatch.contains(route.name),
                                    isUploading: uploadingRouteID == route.id,
                                    isUploadBlocked: uploadingRouteID != nil && uploadingRouteID != route.id,
                                    onSend: { sendToWatch(route) },
                                    onRename: { newName in
                                        store.rename(route, to: newName)
                                    }
                                )
                            }
                            .onDelete { indices in
                                for i in indices {
                                    store.delete(store.routes[i])
                                }
                            }
                        }
                    }
                }
                .navigationTitle("Computa")
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
                    allowedContentTypes: [.xml, .data],
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

                ConnectionStatusBar(connectivity: connectivity)
            }
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
                        store.save(route)
                    }
                }
            }
        case .failure(let error):
            importError = error.localizedDescription
        }
    }
}
