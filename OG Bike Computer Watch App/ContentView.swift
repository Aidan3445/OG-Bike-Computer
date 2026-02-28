//
//  ContentView.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var store = RouteStore()
    @StateObject private var connectivity = ConnectivityManager.shared

    var body: some View {
        NavigationStack {
            Group {
                if store.routes.isEmpty {
                    VStack(spacing: 8) {
                        Image(systemName: "arrow.down.circle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No Routes")
                            .font(.headline)
                        Text("Import a GPX on your iPhone and send it here.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(store.routes) { route in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(route.name)
                                    .font(.headline)
                                Text(formatDistance(route.distance))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .onDelete { indices in
                            for i in indices {
                                store.delete(store.routes[i])
                            }
                        }
                    }
                }
            }
            .navigationTitle("Routes")
        }
        .onAppear {
            ConnectivityManager.shared.onRouteReceived = { route in
                store.save(route)
            }
        }
    }
}

#Preview {
    ContentView()
}
