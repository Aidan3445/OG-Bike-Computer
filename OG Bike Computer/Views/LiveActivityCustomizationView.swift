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
    @State private var editingSlot: Int?
    @State private var showResetConfirm = false

    private var slots: Binding<[LiveActivitySlot]> {
        $userSettings.settings.phoneAlerts.liveActivitySlots
    }

    /// All metric types eligible for Live Activity display.
    private var availableMetrics: [MetricType] { MetricType.liveActivityStats }

    private var phoneAlerts: PhoneAlertPreferences {
        userSettings.settings.phoneAlerts
    }

    private var usesDistanceRemaining: Bool {
        phoneAlerts.liveActivitySlots.contains { $0.metricType == .distanceRemaining }
    }

    private var automaticFallback: MetricType {
        LiveActivitySlot.automaticRemainingFallback(for: phoneAlerts.liveActivitySlots)
    }

    /// Metrics selectable as the no-route stand-in for REMAINING.
    private var fallbackCandidates: [MetricType] {
        MetricType.liveActivityStats.filter { !$0.requiresRoute }
    }

    /// One slot row: icon + metric picker, with a fallback note when the
    /// selected metric only applies to routed rides.
    private func slotRow(_ index: Int) -> some View {
        let slotBinding = slots[index]
        return VStack(alignment: .leading, spacing: 3) {
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
            if slotBinding.metricType.wrappedValue == .distanceRemaining {
                Label(
                    "Shows \(phoneAlerts.resolvedRemainingFallback.label) on rides without a route",
                    systemImage: "arrow.uturn.down"
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .padding(.leading, 32)
            }
        }
    }

    var body: some View {
        Form {
            Section {
                // Interactive preview of the 2x3 grid: tap a cell to change
                // that slot directly.
                LiveActivityPreview(
                    slots: userSettings.settings.phoneAlerts.liveActivitySlots,
                    onSlotTap: { index in editingSlot = index }
                )
                .padding(.vertical, 4)
            } header: {
                Text("Preview")
            } footer: {
                Text("Tap any slot to change it. This mirrors how stats will appear on your Lock Screen during a ride.")
            }

            Section {
                ForEach(0..<3, id: \.self) { index in
                    slotRow(index)
                }
                Toggle("Show in Dynamic Island", isOn: $userSettings.settings.phoneAlerts.showStatsInDynamicIsland)
            } header: {
                Text("Top Row")
            } footer: {
                Text("On devices with a Dynamic Island, the top row also appears in the expanded island view. Takes effect at the next ride.")
            }

            Section {
                ForEach(3..<6, id: \.self) { index in
                    slotRow(index)
                }
            } header: {
                Text("Bottom Row")
            } footer: {
                Text("Choose the metric for each slot, left to right.")
            }

            if usesDistanceRemaining {
                Section {
                    Picker("Fallback Stat", selection: $userSettings.settings.phoneAlerts.distanceRemainingFallback) {
                        Text("Automatic — \(automaticFallback.label)").tag(MetricType?.none)
                        ForEach(fallbackCandidates) { metric in
                            Text(metric.label).tag(MetricType?.some(metric))
                        }
                    }
                } header: {
                    Text("No-Route Fallback")
                } footer: {
                    Text("Remaining distance is only available when following a route. On rides without a route, the fallback stat is shown in its place. Automatic uses the first stat that isn't already in the grid.")
                }
            }

            if phoneAlerts.liveActivitySlots != LiveActivitySlot.defaultSlots
                || phoneAlerts.distanceRemainingFallback != nil
                || !phoneAlerts.showStatsInDynamicIsland {
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Live Activity Stats", preset: userSettings.activePresetName)
        .animation(.default, value: usesDistanceRemaining)
        .confirmationDialog(
            "Reset Live Activity Stats to Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
            Button("Reset", role: .destructive) {
                userSettings.settings.phoneAlerts.liveActivitySlots = LiveActivitySlot.defaultSlots
                userSettings.settings.phoneAlerts.distanceRemainingFallback = nil
                userSettings.settings.phoneAlerts.showStatsInDynamicIsland = true
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Slot assignments, Dynamic Island, and fallback will be restored to their defaults.")
        }
        .sheet(item: Binding(
            get: { editingSlot.map(SlotEditIdentifier.init) },
            set: { editingSlot = $0?.index }
        )) { ident in
            NavigationStack {
                Form {
                    Picker("Metric", selection: $userSettings.settings.phoneAlerts.liveActivitySlots[ident.index].metricType) {
                        ForEach(availableMetrics) { metric in
                            Label(metric.label, systemImage: metric.icon).tag(metric)
                        }
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                .navigationTitle("Slot \(ident.index + 1)")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { editingSlot = nil }
                    }
                }
            }
            .presentationDetents([.medium, .large])
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                NavigationLink {
                    SettingsPresetsView(userSettings: userSettings)
                } label: {
                    Image(systemName: "slider.horizontal.2.gobackward")
                }
            }
        }
    }
}

// MARK: - Live Activity Preview

/// Wraps the editing-slot index so SwiftUI's `.sheet(item:)` can bind to it.
private struct SlotEditIdentifier: Identifiable {
    let index: Int
    var id: Int { index }
}

private struct LiveActivityPreview: View {
    let slots: [LiveActivitySlot]
    let onSlotTap: (Int) -> Void

    var body: some View {
        VStack(spacing: 0) {
            // Top row
            HStack(spacing: 0) {
                ForEach(0..<min(3, slots.count), id: \.self) { i in
                    previewCell(slots[i].metricType, index: i)
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
                    previewCell(slots[i].metricType, index: i)
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

    private func previewCell(_ metric: MetricType, index: Int) -> some View {
        Button {
            onSlotTap(index)
        } label: {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
