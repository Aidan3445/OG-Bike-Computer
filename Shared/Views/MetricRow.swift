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
                .frame(
                    maxWidth: .infinity,
                    alignment: alignment
                )
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value)
                    .font(.system(size: 24, weight: .bold, design: .rounded))
                    .monospacedDigit()
                if !unit.isEmpty {
                    Text(unit)
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
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
