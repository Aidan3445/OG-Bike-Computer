//
//  RideHistoryView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI

struct RideHistoryView: View {
    @ObservedObject var rideStore: RideStore

    var body: some View {
        Group {
            if rideStore.rides.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "bicycle",
                    description: Text("Completed rides from your watch will appear here."))
            } else {
                List {
                    ForEach(rideStore.rides) { ride in
                        RideRow(ride: ride, rideStore: rideStore)
                    }
                    .onDelete { indices in
                        for i in indices {
                            rideStore.delete(rideStore.rides[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("Rides")
    }
}

struct RideRow: View {
    let ride: RideSummary
    let rideStore: RideStore

    @State private var showShareSheet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Image(systemName: ride.activityType.icon)
                    .foregroundStyle(.secondary)
                Text(ride.name)
                    .font(.headline)
                Spacer()
                Button {
                    showShareSheet = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .buttonStyle(.plain)
            }

            Text(ride.date, style: .date)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(String(format: "%.1f mi", ride.distance / 1609.34),
                      systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                Label(formatDuration(ride.movingTime), systemImage: "clock")
                if ride.elevationGain > 0 {
                    Label(String(format: "%.0f ft", ride.elevationGain * 3.28084),
                          systemImage: "arrow.up.right")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack(spacing: 16) {
                Label(String(format: "%.1f mph", ride.avgSpeed * 2.23694),
                      systemImage: "speedometer")
                Label(String(format: "%.0f cal", ride.calories),
                      systemImage: "flame")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .sheet(isPresented: $showShareSheet) {
            if let gpxURL = rideStore.exportGPX(for: ride) {
                ShareSheet(activityItems: [gpxURL])
            }
        }
    }

    private func formatDuration(_ t: TimeInterval) -> String {
        let h = Int(t) / 3600
        let m = (Int(t) % 3600) / 60
        return h > 0 ? "\(h)h \(m)m" : "\(m)m"
    }
}
