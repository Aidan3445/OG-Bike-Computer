//
//  AwaitingRideRow.swift
//  OG Bike Computer
//

import SwiftUI

struct AwaitingRideRow: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .top) {
                Image(systemName: "bicycle")
                    .foregroundStyle(.secondary)
                Text("Waiting for ride from watch")
                    .font(.headline)
                ProgressView()
                    .scaleEffect(0.7)
                    .frame(width: 14, height: 14)
                Spacer()
            }

            Grid(alignment: .leading, horizontalSpacing: 12, verticalSpacing: 4) {
                GridRow {
                    Label("--", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                    Label("--", systemImage: "arrow.up.right")
                    Label("--", systemImage: "arrow.down.right")
                }
                GridRow {
                    Label("--", systemImage: "clock")
                    Label("--", systemImage: "speedometer")
                    Label("--", systemImage: "flame")
                }
            }
            .labelStyle(StatLabelStyle())
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
    }
}
