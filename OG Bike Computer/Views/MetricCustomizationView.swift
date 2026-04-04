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
    @ObservedObject var userSettings: UserSettingsStore
    var profileName: String = ""
    @State private var selectedPage: Int = 0
    @State private var showAddPage = false
    @State private var newPageName = ""
    @State private var showResetConfirm = false
    @State private var editingPageIndex: Int?

    /// Pages from other profiles available for import, excluding any that match a current page
    private var otherProfilePages: [(profileName: String, page: MetricPage)] {
        guard let activeID = userSettings.activePresetID else { return [] }
        let currentPages = metricConfig.config.pages
        return userSettings.presets
            .filter { $0.id != activeID }
            .flatMap { preset in
                preset.metricConfig.pages.map { (profileName: preset.name, page: $0) }
            }
            .filter { item in
                !currentPages.contains { current in
                    current.name == item.page.name
                    && current.slots.map(\.type) == item.page.slots.map(\.type)
                }
            }
    }

    /// Total number of carousel items: pages + 1 "Add Page" card + other profile pages
    private var totalItems: Int { metricConfig.config.pages.count + 1 + otherProfilePages.count }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Carousel of watch previews
                TabView(selection: $selectedPage) {
                    ForEach(Array(metricConfig.config.pages.enumerated()), id: \.element.id) { index, page in
                        NavigationLink {
                            MetricPageEditor(
                                metricConfig: metricConfig,
                                pageIndex: index
                            )
                        } label: {
                            WatchPagePreview(page: page)
                        }
                        .buttonStyle(.plain)
                        .contextMenu {
                            Button {
                                editingPageIndex = index
                            } label: {
                                Label("Edit Page", systemImage: "slider.horizontal.3")
                            }
                            if metricConfig.config.pages.count > 1 {
                                Button(role: .destructive) {
                                    withAnimation {
                                        metricConfig.removePage(at: index)
                                        selectedPage = max(0, min(selectedPage, metricConfig.config.pages.count - 1))
                                        syncToWatch()
                                    }
                                } label: {
                                    Label("Delete Page", systemImage: "trash")
                                }
                            }
                        }
                        .tag(index)
                        .padding(.horizontal, 32)
                    }

                    // "Add Page" card
                    Button {
                        showAddPage = true
                    } label: {
                        AddPageCard()
                    }
                    .buttonStyle(.plain)
                    .tag(metricConfig.config.pages.count)
                    .padding(.horizontal, 32)

                    // Pages from other profiles
                    ForEach(Array(otherProfilePages.enumerated()), id: \.element.page.id) { index, item in
                        Button {
                            importPage(item.page)
                        } label: {
                            ProfilePageCard(page: item.page, profileName: item.profileName)
                        }
                        .buttonStyle(.plain)
                        .tag(metricConfig.config.pages.count + 1 + index)
                        .padding(.horizontal, 32)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: 240)

                // Page dots
                HStack(spacing: 6) {
                    ForEach(0..<totalItems, id: \.self) { i in
                        if i < metricConfig.config.pages.count {
                            Circle()
                                .fill(i == selectedPage ? Color.primary : Color.secondary.opacity(0.4))
                                .frame(width: i == selectedPage ? 8 : 6, height: i == selectedPage ? 8 : 6)
                        } else if i == metricConfig.config.pages.count {
                            // "Add" dot
                            Image(systemName: "plus")
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(i == selectedPage ? Color.primary : Color.secondary.opacity(0.5))
                        } else {
                            // Other profile page dot
                            Circle()
                                .fill(i == selectedPage ? Color.secondary : Color.secondary.opacity(0.2))
                                .frame(width: i == selectedPage ? 7 : 5, height: i == selectedPage ? 7 : 5)
                        }
                    }
                }
                .animation(.spring(response: 0.2), value: selectedPage)
                .padding(.top, 6)
                .padding(.bottom, 4)

                // Page label
                if metricConfig.config.pages.indices.contains(selectedPage) {
                    let page = metricConfig.config.pages[selectedPage]
                    Text(page.name)
                        .font(.headline)
                        .padding(.bottom, 2)
                    Text("\(page.slots.count)/\(MetricPage.maxSlots) metrics")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Text("Tap/Hold to manage")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .padding(.top, 2)
                } else if selectedPage == metricConfig.config.pages.count {
                    Text("Add a new page")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                } else {
                    let profileIdx = selectedPage - metricConfig.config.pages.count - 1
                    if otherProfilePages.indices.contains(profileIdx) {
                        let item = otherProfilePages[profileIdx]
                        Text(item.page.name)
                            .font(.headline)
                            .foregroundStyle(.secondary)
                            .padding(.bottom, 2)
                        Text("From \(item.profileName) · Tap to import")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Button {
                    showResetConfirm = true
                } label: {
                    Text("Reset to Defaults")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.top, 8)
            .padding(.bottom, 16)
        }
        .settingsPageTitle("Customize Metrics", profile: profileName)
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
        .confirmationDialog("Reset all metric pages to defaults?", isPresented: $showResetConfirm, titleVisibility: .visible) {
            Button("Reset to Defaults", role: .destructive) {
                metricConfig.resetToDefault()
                selectedPage = 0
                syncToWatch()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: metricConfig.config.pages.count) { _, count in
            if selectedPage >= count + 1 { selectedPage = max(0, count) }
        }
        // NavigationLink destination triggered by context menu "Edit"
        .navigationDestination(isPresented: Binding(
            get: { editingPageIndex != nil },
            set: { if !$0 { editingPageIndex = nil } }
        )) {
            if let idx = editingPageIndex, metricConfig.config.pages.indices.contains(idx) {
                MetricPageEditor(metricConfig: metricConfig, pageIndex: idx)
            }
        }
    }

    private func importPage(_ page: MetricPage) {
        // Create a copy with a new ID so it's independent
        var imported = page
        imported.id = UUID()
        metricConfig.addPage(imported)
        selectedPage = metricConfig.config.pages.count - 1
        syncToWatch()
    }

    private func syncToWatch() {
        if let data = metricConfig.encodedConfig {
            ConnectivityManager.shared.sendMetricConfig(data)
        }
    }
}

// MARK: - Profile Page Card (greyed-out preview from another profile)

private struct ProfilePageCard: View {
    let page: MetricPage
    let profileName: String

    private let watchWidth: CGFloat  = 148
    private let watchHeight: CGFloat = 182

    var body: some View {
        ZStack {
            // Dimmed watch preview
            WatchPagePreview(page: page)
                .opacity(0.35)

            // Profile name badge
            VStack {
                Spacer()
                HStack(spacing: 4) {
                    Image(systemName: "square.and.arrow.down")
                        .font(.system(size: 10, weight: .semibold))
                    Text(profileName)
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .padding(.vertical, 5)
                .background(.ultraThinMaterial)
                .clipShape(Capsule())
                .padding(.bottom, 12)
            }
        }
        .frame(width: watchWidth, height: watchHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - "Add Page" Card

private struct AddPageCard: View {
    private let watchWidth: CGFloat  = 160
    private let watchHeight: CGFloat = 182

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.black)
                .padding(5)
                .overlay(
                    VStack(spacing: 8) {
                        Image(systemName: "plus.circle")
                            .font(.system(size: 32, weight: .light))
                            .foregroundStyle(.secondary)
                        Text("Add Page")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                    }
                )
        }
        .frame(width: watchWidth, height: watchHeight)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }
}

// MARK: - Page Editor

struct MetricPageEditor: View {
    @ObservedObject var metricConfig: MetricConfigStore
    let pageIndex: Int
    @State private var showMetricPicker = false
    @State private var replacingSlotIndex: Int?
    @State private var showDeleteConfirm = false
    @Environment(\.dismiss) private var dismiss

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
                                    if slot.type.isEstimate {
                                        Text("EST")
                                            .font(.system(size: 8, weight: .bold))
                                            .foregroundStyle(.purple)
                                            .padding(.horizontal, 3)
                                            .padding(.vertical, 1)
                                            .background(.purple.opacity(0.15))
                                            .clipShape(Capsule())
                                    }
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
            ToolbarItem(placement: .primaryAction) {
                EditButton()
            }
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    showDeleteConfirm = true
                } label: {
                    Image(systemName: "trash")
                }
                .disabled(metricConfig.config.pages.count <= 1)
            }
        }
        .confirmationDialog("Delete \"\(page.name)\"?", isPresented: $showDeleteConfirm, titleVisibility: .visible) {
            Button("Delete Page", role: .destructive) {
                metricConfig.removePage(at: pageIndex)
                syncToWatch()
                dismiss()
            }
            Button("Cancel", role: .cancel) {}
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
                            if metric.isEstimate {
                                Text("EST")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.purple)
                                    .padding(.horizontal, 4)
                                    .padding(.vertical, 2)
                                    .background(.purple.opacity(0.15))
                                    .clipShape(Capsule())
                            }
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

struct WatchPagePreview: View {
    let page: MetricPage

    // Scaled down to ~1/3 screen height
    private let watchWidth: CGFloat  = 148
    private let watchHeight: CGFloat = 182

    var body: some View {
        ZStack {
            // Watch body
            RoundedRectangle(cornerRadius: 34)
                .fill(Color(white: 0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: 34)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: 1)
                )

            // Screen
            RoundedRectangle(cornerRadius: 28)
                .fill(Color.black)
                .padding(5)
                .overlay(
                    screenContent
                        .padding(5)
                )
        }
        .frame(width: watchWidth, height: watchHeight)
        .shadow(color: .black.opacity(0.3), radius: 12, y: 6)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
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
        }
        .padding(.top, 10)
        .padding(.horizontal, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(.white)
    }
}
