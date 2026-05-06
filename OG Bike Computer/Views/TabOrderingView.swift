//
//  TabOrderingView.swift
//  OG Bike Computer
//
//  Lets the user reorder the watch's main workout tabs.
//

import SwiftUI

struct TabOrderingView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject var metricConfig: MetricConfigStore

    /// What the resolver sees right now (we always preview against these,
    /// since the user is offline editing — we want all available tabs visible).
    private var availableTabs: [WorkoutTabKey] {
        WorkoutTabOrder.resolve(
            hasRoute: true,
            elevationEnabled: userSettings.settings.ridePreferences.elevationScreen.enabled,
            pages: metricConfig.config.pages,
            stored: userSettings.settings.ridePreferences.tabOrder
        )
    }

    private var orderBinding: Binding<[WorkoutTabKey]> {
        Binding(
            get: { availableTabs },
            set: { userSettings.settings.ridePreferences.tabOrder = $0 }
        )
    }

    var body: some View {
        Form {
            Section {
                let order = availableTabs
                ForEach(order) { key in
                    TabOrderRow(key: key, page: metricPage(for: key))
                }
                .onMove { indices, newOffset in
                    var current = order
                    current.move(fromOffsets: indices, toOffset: newOffset)
                    userSettings.settings.ridePreferences.tabOrder = current
                }
            } header: {
                Text("Drag to reorder. Updates the watch live.")
                    .textCase(nil)
            } footer: {
                Text("The Route Map screen always opens first. Elevation and metric pages can be ordered freely.")
            }

            if userSettings.settings.ridePreferences.tabOrder != nil {
                Section {
                    Button("Reset to Default Order", role: .destructive) {
                        userSettings.settings.ridePreferences.tabOrder = nil
                    }
                }
            }
        }
        .environment(\.editMode, .constant(.active))
        .settingsPageTitle("Tab Order", profile: userSettings.activeProfileName)
    }

    private func metricPage(for key: WorkoutTabKey) -> MetricPage? {
        guard key.kind == .metricPage, let id = key.metricPageID else { return nil }
        return metricConfig.config.pages.first { $0.id == id }
    }
}

private struct TabOrderRow: View {
    let key: WorkoutTabKey
    let page: MetricPage?

    var body: some View {
        HStack(spacing: 12) {
            icon
                .frame(width: 32, height: 32)
                .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 8))
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.body)
                if let subtitle = subtitle {
                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var icon: some View {
        switch key.kind {
        case .routeMap:
            Image(systemName: "map")
                .font(.system(size: 16))
                .foregroundStyle(.blue)
        case .elevation:
            Image(systemName: "mountain.2")
                .font(.system(size: 16))
                .foregroundStyle(.green)
        case .metricPage:
            Image(systemName: "gauge.with.dots.needle.50percent")
                .font(.system(size: 16))
                .foregroundStyle(.yellow)
        }
    }

    private var title: String {
        switch key.kind {
        case .routeMap:    return "Route Map"
        case .elevation:   return "Elevation"
        case .metricPage:  return page?.name ?? "Metric Page"
        }
    }

    private var subtitle: String? {
        switch key.kind {
        case .routeMap:    return "Live navigation map"
        case .elevation:   return "Route elevation profile"
        case .metricPage:
            guard let p = page else { return nil }
            return "\(p.slots.count) metric\(p.slots.count == 1 ? "" : "s")"
        }
    }
}
