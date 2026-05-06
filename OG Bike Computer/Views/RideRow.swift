//
//  RideRow.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import SwiftUI

struct RideRow: View {
    let ride: RideSummary
    let onRename: (String) -> Void
    var isTransferring: Bool = false
    @ObservedObject private var unitState = UnitState.shared

    @State private var showRenameSheet = false
    @State private var editedName = ""

    var body: some View {
        let _ = unitState.preferences
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: ride.activityType.icon)
                    .foregroundStyle(.secondary)
                Text(ride.name)
                    .font(.headline)
                if let uploads = ride.uploads, !uploads.isEmpty {
                    // Show one badge per service (deduplicate in case of retransmit duplicates)
                    let uniqueServices = uploads.uniqueByService()
                    ForEach(uniqueServices) { upload in
                        ServiceBadge(service: upload.service)
                    }
                }
                if ride.wasAutoFinalized == true {
                    Image(systemName: "exclamationmark.circle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .help("Auto-saved when a new ride started")
                }
                if isTransferring {
                    HStack(spacing: 4) {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 0) {
                    Text(ride.date, style: .date)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text(ride.date, style: .time)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Label(formatDistance(ride.distance), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label(ride.elevationGain > 0 ? formatElevation(ride.elevationGain) : "—", systemImage: "arrow.up.right")
                    Label(ride.elevationGain > 0 ? formatElevation(ride.elevationLoss) : "—", systemImage: "arrow.down.right")
                }
                GridRow {
                    Label(formatTime(ride.movingTime), systemImage: "clock")
                    Label(formatSpeed(ride.avgSpeed), systemImage: "speedometer")
                    Label(String(format: "%.0f cal", ride.calories), systemImage: "flame")
                }
            }
            .labelStyle(StatLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .swipeActions(edge: .leading) {
            Button {
                editedName = ride.name
                showRenameSheet = true
            } label: {
                Label("Rename", systemImage: "pencil")
            }
            .tint(.orange)
        }
        .alert("Rename Ride", isPresented: $showRenameSheet) {
            TextField("Ride name", text: $editedName)
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
