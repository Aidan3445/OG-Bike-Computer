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
            // Everything but the name sits on the date line so the name gets the full width.
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Image(systemName: ride.activityType.icon)
                    Text(ride.date.formatted(date: .abbreviated, time: .shortened))
                        .lineLimit(1)
                        .layoutPriority(1)
                    if ride.wasAutoFinalized == true {
                        Image(systemName: "exclamationmark.circle")
                            .help("Auto-saved when a new ride started")
                    }
                    if isTransferring {
                        ProgressView()
                            .scaleEffect(0.7)
                            .frame(width: 14, height: 14)
                    }
                    Spacer(minLength: 0)
                    if let uploads = ride.uploads, !uploads.isEmpty {
                        // One badge per service, in case a retransmit duplicated a record
                        HStack(spacing: 4) {
                            ForEach(uploads.uniqueByService()) { upload in
                                ServiceBadge(service: upload.service)
                            }
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                Text(ride.name)
                    .font(.headline)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Label(formatDistance(ride.distance, grouped: true), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label(ride.elevationGain > 0 ? formatElevation(ride.elevationGain, grouped: true) : "—", systemImage: "arrow.up.right")
                    Label(ride.elevationGain > 0 ? formatElevation(ride.elevationLoss, grouped: true) : "—", systemImage: "arrow.down.right")
                }
                GridRow {
                    Label(formatTime(ride.movingTime), systemImage: "clock")
                    Label(formatSpeed(ride.avgSpeed), systemImage: "speedometer")
                    Label(formatCalories(ride.calories, grouped: true), systemImage: "flame")
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
        .selectAllOnEdit(when: showRenameSheet)
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

#if DEBUG
extension RideSummary {
    /// A ride with every stat past 1,000, to check how separators fit.
    static func previewLong(name: String = "Day 117 - Oak Harbor to Port Angeles", onHold: Bool = false) -> RideSummary {
        RideSummary(id: UUID(), name: name, activityType: .cycling, date: Date(),
                    elapsedTime: 15 * 3600, movingTime: 11 * 3600 + 42 * 60, distance: 1_852_000,
                    calories: 12_345, elevationGain: 9_524, elevationLoss: 8_731,
                    avgSpeed: 7.3, pointCount: 0, trackFilename: "preview.track",
                    isOnHold: onHold)
    }
}

#Preview("Big numbers") {
    List {
        RideRow(ride: .previewLong(), onRename: { _ in })
        RideRow(ride: .previewLong(name: "Short name"), onRename: { _ in })
    }
}
#endif
