//
//  ConnectionStatusBar.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI
import WatchConnectivity

struct ConnectionStatusBar: View {
    @ObservedObject var connectivity: ConnectivityManager
    @ObservedObject var routeStore: RouteStore

    var body: some View {
        HStack(spacing: 12) {
            statusIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.caption.weight(.semibold))

                Text(statusDetail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            if routeStore.storageSize > 0 {
                Text(formattedStorageSize(routeStore.storageSize))
                    .font(.caption.weight(.semibold))
                    .monospacedDigit()
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.ultraThinMaterial)
        .overlay(Divider(), alignment: .top)
    }

    private var statusIcon: some View {
        Image(systemName: iconName)
            .foregroundStyle(iconColor)
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
        if !connectivity.isPaired {
            return "No Apple Watch Paired"
        }
        if !connectivity.isWatchAppInstalled {
            return "Watch App Not Installed"
        }
        #endif
        if connectivity.isReachable {
            return "Watch Connected"
        }
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
