//
//  ConnectionStatusButton.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import SwiftUI
import WatchConnectivity

struct ConnectionStatusButton: View {
    @ObservedObject var connectivity: ConnectivityManager
    @ObservedObject var routeStore: RouteStore

    @State private var showDetail = false

    var body: some View {
        Button {
            showDetail = true
        } label: {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .font(.body.weight(.semibold))
                .frame(width: 32, height: 32)
        }
        .sheet(isPresented: $showDetail) {
            ConnectionDetailSheet(
                connectivity: connectivity,
                routeStore: routeStore
            )
            .presentationDetents([.height(180)])
            .presentationDragIndicator(.visible)
        }
    }

    private var iconName: String {
        if connectivity.activationState != .activated {
            return "bolt.slash"
        }
        #if os(iOS)
        if !connectivity.isPaired {
            return "applewatch.slash"
        }
        if !connectivity.isWatchAppInstalled {
            return "applewatch"
        }
        #endif
        if connectivity.isReachable {
            return "checkmark.circle.fill"
        }
        return "applewatch.radiowaves.left.and.right"
    }

    private var iconColor: Color {
        if connectivity.activationState != .activated { return .red }
        #if os(iOS)
        if !connectivity.isPaired || !connectivity.isWatchAppInstalled { return .red }
        #endif
        if connectivity.isReachable { return .green }
        return .orange
    }
}

private struct ConnectionDetailSheet: View {
    @ObservedObject var connectivity: ConnectivityManager
    @ObservedObject var routeStore: RouteStore

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: iconName)
                    .foregroundStyle(iconColor)
                    .font(.title3.weight(.semibold))

                VStack(alignment: .leading, spacing: 2) {
                    Text(statusTitle)
                        .font(.headline)
                    Text(statusDetail)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            Divider()

            if routeStore.storageSize > 0 {
                HStack {
                    Label("Local storage", systemImage: "internaldrive")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Text(formattedStorageSize(routeStore.storageSize))
                        .font(.subheadline.weight(.semibold))
                        .monospacedDigit()
                }
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var iconName: String {
        if connectivity.activationState != .activated {
            return "bolt.slash"
        }
        #if os(iOS)
        if !connectivity.isPaired {
            return "applewatch.slash"
        }
        if !connectivity.isWatchAppInstalled {
            return "applewatch"
        }
        #endif
        if connectivity.isReachable {
            return "checkmark.circle.fill"
        }
        return "applewatch.radiowaves.left.and.right"
    }

    private var iconColor: Color {
        if connectivity.activationState != .activated { return .red }
        #if os(iOS)
        if !connectivity.isPaired || !connectivity.isWatchAppInstalled { return .red }
        #endif
        if connectivity.isReachable { return .green }
        return .orange
    }

    private var statusTitle: String {
        if connectivity.activationState != .activated {
            return "WatchConnectivity Inactive"
        }
        #if os(iOS)
        if !connectivity.isPaired { return "No Apple Watch Paired" }
        if !connectivity.isWatchAppInstalled { return "Watch App Not Installed" }
        #endif
        if connectivity.isReachable { return "Watch Connected" }
        return "Watch Paired"
    }

    private var statusDetail: String {
        switch connectivity.activationState {
        case .notActivated:
            return "Session not activated"
        case .inactive:
            return "Session inactive"
        case .activated:
            #if os(iOS)
            if !connectivity.isPaired { return "Pair a watch in the Watch app" }
            if !connectivity.isWatchAppInstalled { return "Install the watch app" }
            #endif
            if connectivity.isReachable {
                return "Ready to send routes"
            }
            return "Routes will transfer in the background"
        @unknown default:
            return "Unknown session state"
        }
    }
}
