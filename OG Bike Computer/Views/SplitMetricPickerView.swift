//
//  SplitMetricPickerView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct SplitMetricPickerView: View {
    @Binding var selectedMetrics: [MetricType]

    private let maxSelection = 5

    /// Metrics that make sense for split readouts
    private let availableMetrics: [MetricType] = [
        .movingTime,
        .elapsedTime,
        .averageSpeed,
        .maxSpeed,
        .distance,
        .elevationGain,
        .elevationLoss,
        .heartRate,
        .averageHeartRate,
        .maxHeartRate,
        .calories,
        .powerEstimate,
        .grade,
    ]

    var body: some View {
        List {
            Section {
                ForEach(availableMetrics) { metric in
                    let isSelected = selectedMetrics.contains(metric)
                    let atMax = selectedMetrics.count >= maxSelection && !isSelected

                    Button {
                        if isSelected {
                            selectedMetrics.removeAll { $0 == metric }
                        } else if !atMax {
                            selectedMetrics.append(metric)
                        }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: metric.icon)
                                .frame(width: 24)
                                .foregroundStyle(isSelected ? .blue : .secondary)

                            Text(metric.label)
                                .foregroundStyle(atMax ? .secondary : .primary)

                            Spacer()

                            if isSelected {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.blue)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(atMax)
                }
            } header: {
                Text("Select up to \(maxSelection) stats")
            } footer: {
                Text("These stats will be read aloud at each split. Drag to reorder priority.")
            }
        }
        .navigationTitle("Split Stats")
    }
}
