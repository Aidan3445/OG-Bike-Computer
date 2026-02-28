//
//  ContentView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @StateObject private var store = RouteStore()
    @State private var showFilePicker = false
    @State private var importError: String?

    var body: some View {
        NavigationStack {
            Group {
                if store.routes.isEmpty {
                    ContentUnavailableView(
                        "No Routes",
                        systemImage: "map",
                        description: Text("Import a GPX file to get started."))
                } else {
                    List {
                        ForEach(store.routes) { route in
                            RouteRow(route: route)
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

struct StatLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 2) {
            configuration.icon
            configuration.title
        }
    }
}

struct RouteRow: View {
    let route: Route

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            HStack(spacing: 12) {
                Label(formatDistance(route.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                if route.elevationGain > 0 {
                    Label(formatElevation(route.elevationGain), systemImage: "arrow.up.right")
                }
                if route.elevationLoss > 0 {
                    Label(formatElevation(route.elevationLoss), systemImage: "arrow.down.right")
                }
            }
            .labelStyle(StatLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }

    private func formatDistance(_ meters: Double) -> String {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    }

    private func formatElevation(_ meters: Double) -> String {
        let feet = meters * 3.28084
        return String(format: "%.0f ft", feet)
    }
}

#Preview {
    ContentView()
}
