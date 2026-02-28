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
        if !connectivity.isReachable {
            return "wifi.slash"
        }
        #if os(iOS)
        if !connectivity.isPaired {
            return "applewatch.slash"
        }
        if !connectivity.isWatchAppInstalled {
            return "applewatch"
        }
        #endif
        return "checkmark.circle.fill"
    }

    private var iconColor: Color {
        iconName == "checkmark.circle.fill" ? .green : .orange
    }

    private var statusTitle: String {
        if connectivity.activationState != .activated {
            return "WatchConnectivity Inactive"
        }
        if !connectivity.isReachable {
            return "Watch Not Reachable"
        }
        #if os(iOS)
        if !connectivity.isPaired {
            return "No Apple Watch Paired"
        }
        if !connectivity.isWatchAppInstalled {
            return "Watch App Not Installed"
        }
        #endif
        return "Connected to Apple Watch"
    }

    private var statusDetail: String {
        switch connectivity.activationState {
        case .notActivated:
            return "Session not activated"
        case .inactive:
            return "Session inactive"
        case .activated:
            return connectivity.isReachable
                ? "Ready to send routes"
                : "Waiting for watch to become reachable"
        @unknown default:
            return "Unknown session state"
        }
    }
}
