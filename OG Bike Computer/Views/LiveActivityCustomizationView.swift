//
//  LiveActivityCustomizationView.swift
//  OG Bike Computer
//
//  Settings page for customizing which 6 stats appear in the
//  Live Activity lock-screen widget. Arranged as 2 rows of 3 slots.
//

import SwiftUI

struct LiveActivityCustomizationView: View {
    @ObservedObject var userSettings: UserSettingsStore

    private var slots: Binding<[LiveActivitySlot]> {
        $userSettings.settings.phoneAlerts.liveActivitySlots
    }

    /// All metric types eligible for Live Activity display.
    /// Excludes navigation-only types that are shown in the turn bar instead.
    private var availableMetrics: [MetricType] {
        MetricType.allCases.filter { type in
            switch type {
            case .nextTurnDistance, .nextTurnDirection, .heading, .distanceRemaining:
                return false  // shown in navigation bar, not stat slots
            default:
                return true
            }
        }
    }

    var body: some View {
        Form {
            Section {
                // Preview of the 2x3 grid
                LiveActivityPreview(slots: userSettings.settings.phoneAlerts.liveActivitySlots)
                    .padding(.vertical, 4)
            } header: {
                Text("Preview")
            } footer: {
                Text("This shows how stats will appear on your Lock Screen during a ride.")
            }

            Section {
                ForEach(0..<3, id: \.self) { index in
                    let slotBinding = slots[index]
                    HStack {
                        Image(systemName: slotBinding.metricType.wrappedValue.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Picker("", selection: slotBinding.metricType) {
                            ForEach(availableMetrics) { metric in
                                Text(metric.label).tag(metric)
                            }
                        }
                    }
                }
            } header: {
                Text("Top Row")
            }
            
            Section {
                ForEach(3..<6, id: \.self) { index in
                    let slotBinding = slots[index]
                    HStack {
                        Image(systemName: slotBinding.metricType.wrappedValue.icon)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Picker("", selection: slotBinding.metricType) {
                            ForEach(availableMetrics) { metric in
                                Text(metric.label).tag(metric)
                            }
                        }
                    }
                }
            } header: {
                Text("Bottom Row")
            } footer: {
                Text("Choose which metric appears in each row (from left to right).")
            }

            if userSettings.settings.phoneAlerts.liveActivitySlots != LiveActivitySlot.defaultSlots {
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        userSettings.settings.phoneAlerts.liveActivitySlots = LiveActivitySlot.defaultSlots
                    }
                }
            }
        }
        .settingsPageTitle("Live Activity Stats", profile: userSettings.activeProfileName)
    }
}

// MARK: - Live Activity Preview

private struct LiveActivityPreview: View {
    let slots: [LiveActivitySlot]

    var body: some View {
        VStack(spacing: 0) {
            // Top row
            HStack(spacing: 0) {
                ForEach(0..<min(3, slots.count), id: \.self) { i in
                    previewCell(slots[i].metricType)
                    if i < 2 {
                        Divider().frame(height: 32)
                    }
                }
            }

            Divider()
                .padding(.horizontal, 16)

            // Bottom row
            HStack(spacing: 0) {
                ForEach(3..<min(6, slots.count), id: \.self) { i in
                    previewCell(slots[i].metricType)
                    if i < 5 {
                        Divider().frame(height: 32)
                    }
                }
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func previewCell(_ metric: MetricType) -> some View {
        VStack(spacing: 2) {
            Text("--")
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(metric.label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 6)
    }
}
