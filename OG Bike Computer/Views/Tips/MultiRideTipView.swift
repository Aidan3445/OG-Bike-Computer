//
//  MultiRideTipView.swift
//  OG Bike Computer
//

import SwiftUI

struct MultiRideTipView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "square.stack.3d.up")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                    .padding(.top, 8)

                Text("Multi-Ride Viewer")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Combine multiple rides into a single map and stats summary — perfect for bikepacking trips, multi-day tours, or comparing back-to-back loops.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    TipRow(
                        icon: "checklist",
                        color: .blue,
                        title: "Pick the rides",
                        detail: "In the Rides tab, tap Select and check off the rides you want to combine. The order you tap them determines the segment order on the map."
                    )
                    TipRow(
                        icon: "map",
                        color: .green,
                        title: "Stacked map with connectors",
                        detail: "Each ride is drawn in a different color. When two rides start and end nearby, a grey connector links them so the route reads as one continuous trip."
                    )
                    TipRow(
                        icon: "chart.line.uptrend.xyaxis",
                        color: .purple,
                        title: "Combined elevation & stats",
                        detail: "See the merged elevation profile, totals for distance, time, and elevation, plus per-ride breakdowns in the bottom panel."
                    )
                    TipRow(
                        icon: "square.and.arrow.up",
                        color: .orange,
                        title: "Share the combined view",
                        detail: "Export the merged map and stats as an image, or open individual rides for full details."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("Multi-Ride Viewer")
        .navigationBarTitleDisplayMode(.inline)
    }
}
