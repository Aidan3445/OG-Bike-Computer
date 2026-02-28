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
    @State private var showFilePicker = false
    @State private var importError: String?
    
    @StateObject private var connectivity = ConnectivityManager.shared

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
                                    onSend: { sendToWatch(route) }
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
                .navigationTitle("OG Bike Computer")
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
            }
            ConnectionStatusBar(connectivity: connectivity)
        }
    }
    
    private func sendToWatch(_ route: Route) {
        ConnectivityManager.shared.sendRoute(route) { result in
            if case .failure(let error) = result {
                print("Failed to send route: \(error)")
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
