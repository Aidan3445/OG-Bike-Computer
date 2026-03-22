//
//  MetricCustomizationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/21/26.
//

import SwiftUI

// MARK: - Top-level: Carousel of page previews

struct MetricCustomizationView: View {
    @ObservedObject var metricConfig: MetricConfigStore
    @State private var selectedPage: Int = 0
    @State private var showAddPage = false
    @State private var newPageName = ""

    var body: some View {
        VStack(spacing: 0) {
            // Carousel
            TabView(selection: $selectedPage) {
                ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, page in
                    WatchPagePreview(page: page)
                        .tag(index)
                        .padding(.horizontal, 32)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)

            // Page dots
            HStack(spacing: 6) {
                ForEach(metricConfig.config.pages.indices, id: \.self) { i in
                    Circle()
                        .fill(i == selectedPage ? Color.primary : Color.secondary.opacity(0.4))
                        .frame(width: i == selectedPage ? 8 : 6, height: i == selectedPage ? 8 : 6)
                        .animation(.spring(response: 0.2), value: selectedPage)
                }
            }
            .padding(.top, 10)
            .padding(.bottom, 6)

            // Page name
            if metricConfig.config.pages.indices.contains(selectedPage) {
                Text(metricConfig.config.pages[selectedPage].name)
                    .font(.headline)
                    .padding(.bottom, 4)
                Text("\(metricConfig.config.pages[selectedPage].slots.count)/\(MetricPage.maxSlots) metrics")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .padding(.bottom, 16)
            }

            Divider()

            // Actions
            List {
                if metricConfig.config.pages.indices.contains(selectedPage) {
                    Section {
                        NavigationLink {
                            MetricPageEditor(
                                metricConfig: metricConfig,
                                pageIndex: selectedPage
                            )
                        } label: {
                            Label("Edit This Page", systemImage: "slider.horizontal.3")
                        }

                        Button(role: .destructive) {
                            guard metricConfig.config.pages.count > 1 else { return }
                            metricConfig.removePage(at: selectedPage)
                            selectedPage = max(0, selectedPage - 1)
                            syncToWatch()
                        } label: {
                            Label("Delete This Page", systemImage: "trash")
                        }
                        .disabled(metricConfig.config.pages.count <= 1)
                    }
                }

                Section {
                    Button {
                        showAddPage = true
                    } label: {
                        Label("Add Page", systemImage: "plus.circle")
                    }

                    Button(role: .destructive) {
                        metricConfig.resetToDefault()
                        selectedPage = 0
                        syncToWatch()
                    } label: {
                        Label("Reset to Defaults", systemImage: "arrow.counterclockwise")
                    }
                }
            }
            .listStyle(.insetGrouped)
        }
        .navigationTitle("Customize Metrics")
        .alert("New Page", isPresented: $showAddPage) {
            TextField("Page Name", text: $newPageName)
            Button("Add") {
                let name = newPageName.isEmpty ? "Page \(metricConfig.config.pages.count + 1)" : newPageName
                metricConfig.addPage(MetricPage(name: name, metrics: [.speed, .distance]))
                newPageName = ""
                selectedPage = metricConfig.config.pages.count - 1
                syncToWatch()
            }
            Button("Cancel", role: .cancel) { newPageName = "" }
        }
        // Keep selectedPage in bounds if pages are deleted elsewhere
        .onChange(of: metricConfig.config.pages.count) { _, count in
            if selectedPage >= count { selectedPage = max(0, count - 1) }
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

    private var usedOnOtherPages: Set<MetricType> {
        var types: Set<MetricType> = []
        for (i, p) in metricConfig.config.pages.enumerated() {
            guard i != pageIndex else { continue }
            for slot in p.slots { types.insert(slot.type) }
        }
        return types
    }

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
                WatchPagePreview(page: page)
                    .padding(.vertical, 8)
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
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
        let count = page.slots.filter { $0.type == type }.count
        if count > 1 {
            Text("×\(count)")
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

// MARK: - Watch Page Preview
// Mirrors the watch's DynamicMetricsPage layout using the same MetricRow
// styling (MetricRow lives in the Watch target; we replicate it here).

struct WatchPagePreview: View {
    let page: MetricPage

    // Approximate Apple Watch Ultra 2 / Series 9 45mm display ratio
    private let watchWidth: CGFloat  = 198
    private let watchHeight: CGFloat = 242

    var body: some View {
        ZStack {
            // Watch body
            RoundedRectangle(cornerRadius: 44)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 44)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            // Screen
            RoundedRectangle(cornerRadius: 38)
                .fill(Color.black)
                .padding(6)
                .overlay(
                    screenContent
                        .padding(6)
                )
        }
        .frame(width: watchWidth, height: watchHeight)
        .shadow(color: .black.opacity(0.4), radius: 16, y: 8)
    }

    private var screenContent: some View {
        VStack(spacing: 0) {
            let rows = page.slots.chunked(into: 2)
            ForEach(Array(rows.enumerated()), id: \.offset) { rowIdx, row in
                if rowIdx > 0 {
                    Rectangle()
                        .fill(Color.white.opacity(0.12))
                        .frame(height: 0.5)
                        .padding(.vertical, 5)
                }
                HStack(alignment: .top, spacing: 0) {
                    MetricRow(
                        label: row[0].type.label,
                        value: "--",
                        unit: row[0].type.unit,
                        alignment: .leading
                    )
                    if row.count > 1 {
                        MetricRow(
                            label: row[1].type.label,
                            value: "--",
                            unit: row[1].type.unit,
                            alignment: .trailing
                        )
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}
