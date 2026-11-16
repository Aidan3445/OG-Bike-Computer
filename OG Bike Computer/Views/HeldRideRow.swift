//
//  HeldRideRow.swift
//  OG Bike Computer
//

import SwiftUI

struct HeldRideRow: View {
    let ride: RideSummary
    @ObservedObject private var unitState = UnitState.shared

    var body: some View {
        let _ = unitState.preferences
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: "hand.raised.fill")
                    .foregroundStyle(.orange)
                Text(ride.name)
                    .font(.headline)
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
    }
}

#if DEBUG
#Preview("Big numbers") {
    List {
        HeldRideRow(ride: .previewLong(onHold: true))
    }
}
#endif
