//
//  RouteRow.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct RouteRow: View {
    let route: Route
    let isOnWatch: Bool
    let onSend: () -> Void

    @State private var showOverwriteAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(route.name)
                .font(.headline)
            HStack(spacing: 12) {
                Button {
                    if isOnWatch {
                        showOverwriteAlert = true
                    } else {
                        onSend()
                    }
                } label: {
                    Image(systemName: isOnWatch ? "checkmark.circle.fill" : "arrow.up.circle")
                        .font(.title2)
                        .foregroundStyle(isOnWatch ? .green : .blue)
                }
                .buttonStyle(.plain)

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
        .alert("Route Already on Watch", isPresented: $showOverwriteAlert) {
            Button("Replace", role: .destructive) {
                onSend()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(route.name)\" is already on your watch. Sending will replace the existing version.")
        }
    }
}
