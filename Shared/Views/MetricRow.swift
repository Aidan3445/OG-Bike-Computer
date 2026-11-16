//
//  MetricRow.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct MetricRow: View {
    let label: String
    let value: String
    let unit: String
    let alignment: Alignment

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(label)
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
                .frame(
                    maxWidth: .infinity,
                    alignment: alignment
                )
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                if !unit.isEmpty {
                    // Fixed so the value shrinks first.
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                }
            }
            .frame(
                maxWidth: .infinity,
                alignment: alignment
            )
        }
    }
}

#Preview("L") {
    MetricRow(label: "SPEED", value: "18.4", unit: "mph", alignment: .leading)
}

#Preview("R") {
    MetricRow(label: "SPEED", value: "18.4", unit: "mph", alignment: .trailing)
}

#Preview("C") {
    MetricRow(label: "SPEED", value: "18.4", unit: "mph", alignment: .center)
}

#Preview("41 mm, long values", traits: .fixedLayout(width: 176, height: 215)) {
    VStack(spacing: 4) {
        MetricRow(label: "MOVING TIME", value: "10:45:12", unit: "", alignment: .center)
        Divider()
        HStack {
            MetricRow(label: "AVG SPEED", value: "18.7", unit: "mph", alignment: .leading)
            Spacer()
            MetricRow(label: "ELAPSED", value: "11:02:37", unit: "", alignment: .trailing)
        }
        Divider()
        HStack {
            MetricRow(label: "DISTANCE", value: "181.4", unit: "mi", alignment: .leading)
            Spacer()
            MetricRow(label: "HEART RATE", value: "152", unit: "bpm", alignment: .trailing)
        }
    }
    .padding(.horizontal, 4)
}
