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
    let isUploading: Bool
    let isQueued: Bool
    let isUploadBlocked: Bool
    let canSendToWatch: Bool
    let onSend: () -> Void
    @ObservedObject private var unitState = UnitState.shared
    let onRename: (String) -> Void

    @State private var showOverwriteAlert = false
    @State private var showRenameSheet = false
    @State private var editedName: String = ""

    var body: some View {
        let _ = unitState.preferences
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Text(route.name)
                    .font(.headline)
                if let source = route.source {
                    ServiceBadge(service: source.service)
                }
            }
            HStack(spacing: 12) {
                if canSendToWatch {
                    Button {
                        if isUploading || isQueued || isUploadBlocked { return }
                        if isOnWatch {
                            showOverwriteAlert = true
                        } else {
                            onSend()
                        }
                    } label: {
                        Group {
                            if isUploading {
                                ProgressView()
                            } else if isQueued {
                                Image(systemName: "clock.arrow.circlepath")
                            } else {
                                Image(systemName: isOnWatch ? "checkmark.circle.fill" : "arrow.up.circle")
                            }
                        }
                        .font(.title2)
                        .foregroundStyle(buttonColor(
                            isUploading: isUploading,
                            isQueued: isQueued,
                            isUploadBlocked: isUploadBlocked,
                            isOnWatch: isOnWatch
                        ))
                    }
                    .buttonStyle(.plain)
                    .disabled(isUploadBlocked || isQueued)
                }

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
        .opacity(isUploadBlocked ? 0.5 : 1.0)
        .swipeActions(edge: .leading) {
            Button {
                editedName = route.name
                showRenameSheet = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .alert("Route Already on Watch", isPresented: $showOverwriteAlert) {
            Button("Replace", role: .destructive) {
                onSend()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("\"\(route.name)\" is already on your watch. Sending will replace the existing version.")
        }
        .alert("Rename Route", isPresented: $showRenameSheet) {
            TextField("Route name", text: $editedName)
            Button("Save") {
                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    onRename(trimmed)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
