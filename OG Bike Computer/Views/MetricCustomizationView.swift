//
//  MetricCustomizationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import SwiftUI

struct MetricCustomizationView: View {
    @ObservedObject var metricConfig: MetricConfigStore
    @State private var showAddPage = false
    @State private var newPageName = ""

    var body: some View {
        List {
            Section {
                ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, page in
                    NavigationLink {
                        MetricPageEditor(
                            metricConfig: metricConfig,
                            pageIndex: index
                        )
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(page.name)
                                    .font(.headline)
                                Text("\(page.slots.count)/\(MetricPage.maxSlots) metrics")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("Page \(index + 1)")
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                        }
                    }
                }
                .onMove { source, destination in
                    metricConfig.movePage(from: source, to: destination)
                    syncToWatch()
                }
                .onDelete { indices in
                    for i in indices.sorted().reversed() {
                        metricConfig.removePage(at: i)
                    }
                    syncToWatch()
                }
            } header: {
                Text("Metric Pages")
            } footer: {
                Text("Pages appear as vertical tabs on the watch during a ride. Drag to reorder, swipe to delete.")
            }

            Section {
                Button {
                    showAddPage = true
                } label: {
                    Label("Add Page", systemImage: "plus.circle")
                }

                Button(role: .destructive) {
                    metricConfig.resetToDefault()
                    syncToWatch()
                } label: {
                    Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                }
            }
        }
        .navigationTitle("Customize Metrics")
        .toolbar {
            EditButton()
        }
        .alert("New Page", isPresented: $showAddPage) {
            TextField("Page Name", text: $newPageName)
            Button("Add") {
                let name = newPageName.isEmpty ? "Page \(metricConfig.config.pages.count + 1)" : newPageName
                metricConfig.addPage(MetricPage(name: name, metrics: [.speed, .distance]))
                newPageName = ""
                syncToWatch()
            }
            Button("Cancel", role: .cancel) {
                newPageName = ""
            }
        }
    }

    private func syncToWatch() {
        if let data = metricConfig.encodedConfig {
            ConnectivityManager.shared.sendMetricConfig(data)
        }
    }
}

// MARK: - Page Editor

struct MetricPageEditor: View {
    @ObservedObject var metricConfig: MetricConfigStore
    let pageIndex: Int
    @State private var showMetricPicker = false
    @State private var replacingSlotIndex: Int?

    private var page: MetricPage {
        guard metricConfig.config.pages.indices.contains(pageIndex) else {
            return MetricPage(name: "", metrics: [])
        }
        return metricConfig.config.pages[pageIndex]
    }

    /// All metric types used across all OTHER pages
    private var usedOnOtherPages: Set<MetricType> {
        var types: Set<MetricType> = []
        for (i, p) in metricConfig.config.pages.enumerated() {
            guard i != pageIndex else { continue }
            for slot in p.slots { types.insert(slot.type) }
        }
        return types
    }

    /// All metric types used on THIS page
    private var usedOnThisPage: Set<MetricType> {
        Set(page.slots.map(\.type))
    }

    var body: some View {
        List {
            Section {
                TextField("Page Name", text: Binding(
                    get: { page.name },
                    set: { newName in
                        guard metricConfig.config.pages.indices.contains(pageIndex) else { return }
                        metricConfig.config.pages[pageIndex].name = newName
                    }
                ))
            } header: {
                Text("Name")
            }

            Section {
                ForEach(page.slots) { slot in
                    let idx = page.slots.firstIndex(where: { $0.id == slot.id }) ?? 0
                    Button {
                        replacingSlotIndex = idx
                        showMetricPicker = true
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: slot.type.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(spacing: 4) {
                                    Text(slot.type.label)
                                        .font(.body)
                                        .foregroundStyle(.primary)
                                    usageBadge(for: slot.type)
                                }
                                Text(metricDescription(slot.type))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            positionBadge(for: idx)
                        }
                    }
                }
                .onMove { source, destination in
                    guard metricConfig.config.pages.indices.contains(pageIndex) else { return }
                    metricConfig.config.pages[pageIndex].slots.move(fromOffsets: source, toOffset: destination)
                    syncToWatch()
                }
                .onDelete { indices in
                    guard metricConfig.config.pages.indices.contains(pageIndex) else { return }
                    metricConfig.config.pages[pageIndex].slots.remove(atOffsets: indices)
                    syncToWatch()
                }
            } header: {
                Text("Metrics (\(page.slots.count)/\(MetricPage.maxSlots))")
            } footer: {
                Text("Metrics are shown in rows of 2 on the watch. Tap to change, drag to reorder.")
            }

            Section {
                Button {
                    replacingSlotIndex = nil
                    showMetricPicker = true
                } label: {
                    Label("Add Metric", systemImage: "plus.circle")
                }
                .disabled(page.slots.count >= MetricPage.maxSlots)
            }

            Section {
                WatchPreview(slots: page.slots)
            } header: {
                Text("Preview")
            }
        }
        .navigationTitle(page.name)
        .toolbar {
            EditButton()
        }
        .sheet(isPresented: $showMetricPicker) {
            MetricPickerSheet(
                usedOnThisPage: usedOnThisPage,
                usedOnOtherPages: usedOnOtherPages,
                onSelect: { metric in
                    guard metricConfig.config.pages.indices.contains(pageIndex) else { return }
                    if let replaceIdx = replacingSlotIndex,
                       metricConfig.config.pages[pageIndex].slots.indices.contains(replaceIdx) {
                        metricConfig.config.pages[pageIndex].slots[replaceIdx].type = metric
                    } else {
                        guard metricConfig.config.pages[pageIndex].slots.count < MetricPage.maxSlots else { return }
                        metricConfig.config.pages[pageIndex].slots.append(MetricSlot(type: metric))
                    }
                    replacingSlotIndex = nil
                    syncToWatch()
                }
            )
        }
    }

    @ViewBuilder
    private func positionBadge(for idx: Int) -> some View {
        Text(idx % 2 == 0 ? "L" : "R")
            .font(.caption2.weight(.bold))
            .foregroundStyle(.secondary)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(.secondary.opacity(0.15))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private func usageBadge(for type: MetricType) -> some View {
        let dupOnThisPage = page.slots.filter { $0.type == type }.count > 1
        if dupOnThisPage {
            Text("×\(page.slots.filter { $0.type == type }.count)")
                .font(.caption2.weight(.bold))
                .foregroundStyle(.orange)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(.orange.opacity(0.15))
                .clipShape(Capsule())
        } else if usedOnOtherPages.contains(type) {
            Image(systemName: "doc.on.doc")
                .font(.system(size: 9))
                .foregroundStyle(.secondary)
        }
    }

    private func syncToWatch() {
        if let data = metricConfig.encodedConfig {
            ConnectivityManager.shared.sendMetricConfig(data)
        }
    }

    private func metricDescription(_ metric: MetricType) -> String {
        switch metric {
        case .speed: return "Current speed"
        case .averageSpeed: return "Average over ride"
        case .maxSpeed: return "Highest recorded"
        case .distance: return "Total distance"
        case .distanceRemaining: return "Route remaining"
        case .elapsedTime: return "Wall clock time"
        case .movingTime: return "Time in motion"
        case .heartRate: return "Current BPM"
        case .averageHeartRate: return "Average BPM"
        case .maxHeartRate: return "Peak BPM"
        case .calories: return "Active calories"
        case .currentElevation: return "GPS altitude"
        case .elevationGain: return "Total climbed"
        case .elevationLoss: return "Total descended"
        case .highestElevation: return "Peak altitude"
        case .grade: return "Current slope %"
        case .powerEstimate: return "Estimated watts"
        case .nextTurnDistance: return "Distance to turn"
        case .nextTurnDirection: return "Turn direction"
        case .heading: return "Compass bearing"
        }
    }
}

// MARK: - Metric Picker

struct MetricPickerSheet: View {
    let usedOnThisPage: Set<MetricType>
    let usedOnOtherPages: Set<MetricType>
    let onSelect: (MetricType) -> Void
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(MetricType.allCases) { metric in
                    Button {
                        onSelect(metric)
                        dismiss()
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: metric.icon)
                                .foregroundStyle(.blue)
                                .frame(width: 24)
                            VStack(alignment: .leading) {
                                Text(metric.label)
                                    .foregroundStyle(.primary)
                                Text(metric.unit.isEmpty ? "—" : metric.unit)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if metric.requiresRoute {
                                Image(systemName: "map")
                                    .font(.caption)
                                    .foregroundStyle(.orange)
                            }
                            if usedOnThisPage.contains(metric) {
                                Text("this page")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.blue)
                                    .clipShape(Capsule())
                            } else if usedOnOtherPages.contains(metric) {
                                Text("other page")
                                    .font(.caption2)
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 5)
                                    .padding(.vertical, 2)
                                    .background(.secondary)
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
            .navigationTitle("Choose Metric")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Watch Preview

private struct WatchPreview: View {
    let slots: [MetricSlot]

    var body: some View {
        VStack(spacing: 0) {
            let rows = slots.chunked(into: 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if rowIdx > 0 {
                    Divider()
                        .overlay(Color.gray.opacity(0.4))
                        .padding(.vertical, 3)
                }
                HStack(spacing: 0) {
                    // Left metric
                    previewMetric(row[0].type, alignment: .leading)

                    Spacer(minLength: 4)

                    // Right metric (right-aligned to match watch)
                    if row.count > 1 {
                        previewMetric(row[1].type, alignment: .leading)
                    }
                }
            }
        }
        .padding(12)
        .background(Color.black)
        .foregroundStyle(.white)
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .frame(maxWidth: 200)
        .frame(maxWidth: .infinity)
    }

    private func previewMetric(_ type: MetricType, alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 0) {
            Text(type.label)
                .font(.system(size: 8, weight: .medium))
                .foregroundStyle(.gray)
            HStack(alignment: .firstTextBaseline, spacing: 1) {
                Text("--")
                    .font(.system(size: 18, weight: .bold, design: .rounded))
                if !type.unit.isEmpty {
                    Text(type.unit)
                        .font(.system(size: 7))
                        .foregroundStyle(.gray)
                }
            }
        }
    }
}
