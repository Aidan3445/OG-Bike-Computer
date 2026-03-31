//
//  SplitMetricPickerView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct SplitMetricPickerView: View {
    @Binding var metrics: [SplitMetricConfig]

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
            // Selected metrics with scope pickers
            if !metrics.isEmpty {
                Section {
                    ForEach(metrics.indices, id: \.self) { idx in
                        HStack(spacing: 12) {
                            Image(systemName: metrics[idx].metric.icon)
                                .frame(width: 24)
                                .foregroundStyle(.blue)

                            Text(metrics[idx].metric.label)

                            Spacer()

                            Picker("", selection: $metrics[idx].scope) {
                                ForEach(StatScope.allCases, id: \.self) { scope in
                                    Text(scope.label).tag(scope)
                                }
                            }
                            .pickerStyle(.menu)
                            .frame(width: 80)
                        }
                    }
                    .onDelete { indices in
                        metrics.remove(atOffsets: indices)
                    }
                } header: {
                    Text("Selected Stats")
                } footer: {
                    Text("Scope controls whether the stat reads for the split, the whole ride, or both. Split stats are read first, then ride stats.")
                }
            }

            // Available metrics to add
            Section {
                ForEach(availableMetrics) { metric in
                    let isSelected = metrics.contains { $0.metric == metric }
                    let atMax = metrics.count >= maxSelection && !isSelected

                    Button {
                        if isSelected {
                            metrics.removeAll { $0.metric == metric }
                        } else if !atMax {
                            metrics.append(SplitMetricConfig(metric: metric, scope: .split))
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
                Text("Add Stats (up to \(maxSelection))")
            }
        }
        .navigationTitle("Split Stats")
    }
}
