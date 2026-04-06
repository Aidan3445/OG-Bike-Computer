//
//  MapCustomizationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/3/26.
//

import SwiftUI

struct MapCustomizationView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @ObservedObject private var unitState = UnitState.shared
    @State private var showProfileImport = false

    private var config: Binding<MapScreenConfig> {
        $userSettings.settings.ridePreferences.mapScreen
    }

    /// Map configs from other profiles available for import, excluding any identical to the current config
    private var otherProfileConfigs: [(profileName: String, config: MapScreenConfig)] {
        guard let activeID = userSettings.activePresetID else { return [] }
        let current = userSettings.settings.ridePreferences.mapScreen
        return userSettings.presets
            .filter { $0.id != activeID }
            .map { (profileName: $0.name, config: $0.settings.ridePreferences.mapScreen) }
            .filter { $0.config != current }
    }

    var body: some View {
        Form {
            previewSection
            mapDetailSection
            statsSection
            displaySection
            zoomSection
            routeColorSection
            overlaySection
            resetSection
        }
        .settingsPageTitle("Map Screen", profile: userSettings.activeProfileName)
        .toolbar {
            if !otherProfileConfigs.isEmpty {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showProfileImport = true
                    } label: {
                        Image(systemName: "square.and.arrow.down.on.square")
                    }
                }
            }
        }
        .sheet(isPresented: $showProfileImport) {
            MapConfigImportSheet(
                configs: otherProfileConfigs,
                onImport: { imported in
                    userSettings.settings.ridePreferences.mapScreen = imported
                }
            )
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        Section {
            MapScreenPreview(config: userSettings.settings.ridePreferences.mapScreen)
                .listRowInsets(EdgeInsets())
                .listRowBackground(Color.clear)
        } header: {
            Text("Preview")
        }
    }

    // MARK: - Map Detail

    @ViewBuilder
    private var mapDetailSection: some View {
        Section {
            Toggle("Map Background", isOn: Binding(
                get: { userSettings.settings.ridePreferences.mapScreen.mapDetail == .on },
                set: { userSettings.settings.ridePreferences.mapScreen.mapDetail = $0 ? .on : .off }
            ))
        } header: {
            Label("Map Background", systemImage: "map.fill")
        } footer: {
            if userSettings.settings.ridePreferences.mapScreen.mapDetail == .on {
                Text("Shows a map underneath your route. Uses more battery and requires phone connectivity for map tiles. Also expect longer loading times when starting a workout.")
            } else {
                Text("Route lines are drawn on a plain black background. Lightest battery usage.")
            }
        }
    }

    // MARK: - Stats

    @ViewBuilder
    private var statsSection: some View {
        Section {
            Picker("Primary Stat", selection: config.primaryStat) {
                ForEach(MapStatType.allCases) { type in
                    Label(type.label, systemImage: type.icon).tag(type)
                }
            }

            Toggle("Show Turn Info", isOn: config.showTurnInfo)
        } header: {
            Label("Map Overlay Stats", systemImage: "text.badge.star")
        } footer: {
            Text("Configure which stats appear in the top-left overlay on the map screen.")
        }

        Section("Secondary Stats") {
            ForEach(Array(userSettings.settings.ridePreferences.mapScreen.secondaryStats.enumerated()), id: \.offset) { index, stat in
                HStack {
                    Picker("Slot \(index + 1)", selection: Binding(
                        get: { stat },
                        set: { userSettings.settings.ridePreferences.mapScreen.secondaryStats[index] = $0 }
                    )) {
                        ForEach(MapStatType.allCases) { type in
                            Label(type.label, systemImage: type.icon).tag(type)
                        }
                    }

                    Button(role: .destructive) {
                        userSettings.settings.ridePreferences.mapScreen.secondaryStats.remove(at: index)
                    } label: {
                        Image(systemName: "minus.circle.fill")
                            .foregroundStyle(.red)
                    }
                    .buttonStyle(.plain)
                }
            }

            if userSettings.settings.ridePreferences.mapScreen.secondaryStats.count < MapScreenConfig.maxSecondaryStats {
                Button {
                    userSettings.settings.ridePreferences.mapScreen.secondaryStats.append(.distance)
                } label: {
                    Label("Add Stat", systemImage: "plus.circle")
                }
            }
        }
    }

    // MARK: - Display

    @ViewBuilder
    private var displaySection: some View {
        Section {
            Toggle("Full Route Toggle Button", isOn: config.showFullRouteToggle)
            Toggle("Compass Direction", isOn: config.showHeading)
        } header: {
            Label("Display", systemImage: "map")
        } footer: {
            Text("The full route toggle lets you switch between zoomed breadcrumb and full route views mid-ride. Compass direction shows your heading (N, NE, E, etc.).")
        }
    }

    // MARK: - Zoom

    private var isImperial: Bool { currentUnits.distance == .miles }

    /// Format a distance in meters for the zoom picker labels
    private func zoomLabel(_ meters: Double) -> String {
        if isImperial {
            let feet = meters * 3.28084
            if feet >= 2640 { // 0.5 miles
                let miles = meters / 1609.34
                if miles == Double(Int(miles)) {
                    return "\(Int(miles)) mi"
                }
                return String(format: "%.1f mi", miles)
            }
            return "\(Int(round(feet))) ft"
        }
        return "\(Int(meters))m"
    }

    @ViewBuilder
    private var zoomSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 4) {
                Text("Closest Zoom")
                Picker("Closest Zoom", selection: config.zoomMin) {
                    Text(zoomLabel(100)).tag(100.0)
                    Text(zoomLabel(150)).tag(150.0)
                    Text(zoomLabel(200)).tag(200.0)
                    Text(zoomLabel(300)).tag(300.0)
                    Text(zoomLabel(400)).tag(400.0)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("Farthest Zoom")
                Picker("Farthest Zoom", selection: config.zoomMax) {
                    Text(zoomLabel(800)).tag(800.0)
                    Text(zoomLabel(1200)).tag(1200.0)
                    Text(zoomLabel(1600)).tag(1600.0)
                    Text(zoomLabel(2400)).tag(2400.0)
                    Text(zoomLabel(3200)).tag(3200.0)
                }
                .pickerStyle(.segmented)
            }

            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text("Default Zoom")
                    Spacer()
                    Text(zoomLabel(userSettings.settings.ridePreferences.mapScreen.defaultZoom))
                        .foregroundStyle(.secondary)
                }
                let zMin = userSettings.settings.ridePreferences.mapScreen.zoomMin
                let zMax = userSettings.settings.ridePreferences.mapScreen.zoomMax
                Slider(
                    value: config.defaultZoom,
                    in: zMin...max(zMin + 50, zMax),
                    step: 50
                )
                .onChange(of: zMin) { _, newMin in
                    if userSettings.settings.ridePreferences.mapScreen.defaultZoom < newMin {
                        userSettings.settings.ridePreferences.mapScreen.defaultZoom = newMin
                    }
                }
                .onChange(of: zMax) { _, newMax in
                    if userSettings.settings.ridePreferences.mapScreen.defaultZoom > newMax {
                        userSettings.settings.ridePreferences.mapScreen.defaultZoom = newMax
                    }
                }
            }
        } header: {
            Label("Zoom Range", systemImage: "magnifyingglass")
        } footer: {
            Text("Set the closest and farthest zoom levels, and the default zoom when starting a ride. Zoom levels are the visible distance around you.")
        }
    }

    // MARK: - Route Color

    @ViewBuilder
    private var routeColorSection: some View {
        Section {
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 5), spacing: 12) {
                ForEach(RouteColor.allCases, id: \.self) { color in
                    Button {
                        userSettings.settings.ridePreferences.mapScreen.routeAheadColor = color
                    } label: {
                        ZStack {
                            Circle()
                                .fill(color.color)
                                .frame(width: 36, height: 36)
                            if userSettings.settings.ridePreferences.mapScreen.routeAheadColor == color {
                                Circle()
                                    .strokeBorder(.white, lineWidth: 3)
                                    .frame(width: 36, height: 36)
                                Image(systemName: "checkmark")
                                    .font(.system(size: 12, weight: .bold))
                                    .foregroundStyle(color == .white ? .black : .white)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        } header: {
            Label("Route Line Color", systemImage: "paintbrush")
        } footer: {
            Text("The color of the route ahead on the breadcrumb map. Completed route is always shown in green.")
        }
    }

    // MARK: - Overlay

    @ViewBuilder
    private var overlaySection: some View {
        Section {
            Toggle("Turn Navigation Overlay", isOn: config.showTurnOverlay)
        } header: {
            Label("Metric Screen Overlay", systemImage: "rectangle.on.rectangle")
        } footer: {
            Text("When enabled, a brief map overlay flashes on the metric screen when approaching a turn. This helps with navigation without needing to swipe to the map.")
        }
    }

    // MARK: - Reset

    @ViewBuilder
    private var resetSection: some View {
        if userSettings.settings.ridePreferences.mapScreen != .default {
            Section {
                Button("Reset Map Settings to Defaults", role: .destructive) {
                    userSettings.settings.ridePreferences.mapScreen = .default
                }
            }
        }
    }
}

// MARK: - Map Screen Preview (annotated)

struct MapScreenPreview: View {
    let config: MapScreenConfig

    private let watchWidth: CGFloat = 160
    private let watchHeight: CGFloat = 196

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            // Left callouts
            VStack(alignment: .trailing, spacing: 0) {
                Spacer().frame(height: 24)

                if config.primaryStat != .none {
                    callout(config.primaryStat.label, color: .blue)
                    Spacer().frame(height: 2)
                }

                if config.showTurnInfo {
                    callout("Turn Info", color: .yellow)
                    Spacer().frame(height: 2)
                }

                ForEach(Array(config.secondaryStats.enumerated()), id: \.offset) { _, stat in
                    if stat != .none {
                        callout(stat.label, color: .secondary)
                        Spacer().frame(height: 1)
                    }
                }

                Spacer()

                callout("Zoom out", color: .secondary)
                    .padding(.bottom, 18)
            }
            .frame(width: 70, alignment: .trailing)

            // Watch preview
            watchBody

            // Right callouts
            VStack(alignment: .leading, spacing: 0) {
                Spacer().frame(height: 22)

                if config.showFullRouteToggle {
                    callout("Route Toggle", color: .secondary, leading: true)
                    Spacer().frame(height: 10)
                }

                if config.showHeading {
                    callout("Heading", color: .secondary, leading: true)
                }

                Spacer()

                callout("Zoom in", color: .secondary, leading: true)
                    .padding(.bottom, 18)
            }
            .frame(width: 70, alignment: .leading)
        }
        .frame(maxWidth: .infinity, alignment: .center)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func callout(_ text: String, color: Color, leading: Bool = false) -> some View {
        HStack(spacing: 2) {
            if !leading {
                Text(text)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color)
                Image(systemName: leading ? "arrow.left" : "arrow.right")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(color.opacity(0.6))
            } else {
                Image(systemName: "arrow.left")
                    .font(.system(size: 6, weight: .bold))
                    .foregroundStyle(color.opacity(0.6))
                Text(text)
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(color)
            }
        }
    }

    private var watchBody: some View {
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
    }

    private var screenContent: some View {
        ZStack {
            // Mock map background
            RoundedRectangle(cornerRadius: 23)
                .fill(Color(white: 0.05))

            // Map detail background hint
            if config.mapDetail == .on {
                mockMapBackground
            }

            // Mock route line
            mockRouteLine

            // Stats overlay (top-left)
            VStack(spacing: 0) {
                HStack(alignment: .top, spacing: 4) {
                    // Left: stats
                    VStack(alignment: .leading, spacing: 1) {
                        if config.primaryStat != .none {
                            HStack(spacing: 2) {
                                Text(mockValue(config.primaryStat))
                                    .font(.system(size: 11, weight: .bold, design: .rounded))
                                    .monospacedDigit()
                                Text(mockUnit(config.primaryStat))
                                    .font(.system(size: 6))
                                    .foregroundStyle(.secondary)
                            }
                        }

                        if config.showTurnInfo {
                            HStack(spacing: 3) {
                                Image(systemName: "arrow.turn.up.right")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(.yellow)
                                Text("0.3 mi")
                                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                            }
                        }

                        ForEach(Array(config.secondaryStats.enumerated()), id: \.offset) { index, stat in
                            if stat != .none {
                                Text(mockDisplayValue(stat))
                                    .font(.system(size: 8, weight: .semibold, design: .rounded))
                                    .foregroundStyle(index == config.secondaryStats.count - 1 ? .secondary : .primary)
                            }
                        }
                    }
                    .padding(.horizontal, 4)
                    .padding(.vertical, 3)
                    .background(.black.opacity(0.6))
                    .clipShape(RoundedRectangle(cornerRadius: 6))

                    Spacer()

                    // Right: toggle + heading
                    VStack(spacing: 2) {
                        if config.showFullRouteToggle {
                            Image(systemName: "map")
                                .font(.system(size: 10, weight: .bold))
                                .frame(width: 22, height: 22)
                                .background(.ultraThinMaterial)
                                .clipShape(Circle())
                        }

                        if config.showHeading {
                            Text("NE")
                                .font(.system(size: 8, weight: .bold))
                                .foregroundStyle(.white.opacity(0.7))
                        }
                    }
                }
                .padding(.horizontal, 6)
                .padding(.top, 12)

                Spacer()

                // Zoom controls
                HStack {
                    Image(systemName: "minus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())

                    Spacer()

                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .frame(width: 20, height: 20)
                        .background(.ultraThinMaterial)
                        .clipShape(Circle())
                }
                .padding(.horizontal, 8)
                .padding(.bottom, 10)
            }

            // Rider dot
            Circle()
                .fill(.white)
                .frame(width: 8, height: 8)
                .overlay(
                    Circle().fill(.blue).frame(width: 6, height: 6)
                )
                .offset(y: watchHeight * 0.05)
        }
    }

    private var mockRouteLine: some View {
        Canvas { context, size in
            let midX = (size.width / 2) - 1 // -1 offset to align with dot
            let bottom = size.height * 1
            let top = 0

            // Behind (green, faded)
            var behind = Path()
            behind.move(to: CGPoint(x: midX - 5, y: bottom))
            behind.addQuadCurve(
                to: CGPoint(x: midX, y: size.height * 0.55),
                control: CGPoint(x: midX + 15, y: size.height * 0.65))
            context.stroke(behind, with: .color(.green.opacity(0.4)),
                          style: StrokeStyle(lineWidth: 4, lineCap: .round))

            // Ahead (configured color)
            var ahead = Path()
            ahead.move(to: CGPoint(x: midX, y: size.height * 0.55))
            ahead.addCurve(
                to: CGPoint(x: Int(midX) + 20, y: top),
                control1: CGPoint(x: midX - 20, y: size.height * 0.35),
                control2: CGPoint(x: midX + 30, y: size.height * 0.2))
            context.stroke(ahead, with: .color(config.routeAheadColor.color),
                          style: StrokeStyle(lineWidth: 4, lineCap: .round))
        }
    }

    /// Faint mock road lines to hint at map background mode
    private var mockMapBackground: some View {
        Canvas { context, size in
            let roadColor = Color.gray.opacity(0.15)
            let style = StrokeStyle(lineWidth: 1.5, lineCap: .round)

            // Horizontal "roads"
            let yOffsets: [(frac: Double, endOff: CGFloat, ctrlOff: CGFloat)] = [
                (0.25, 4, -6), (0.45, -3, 8), (0.7, 5, -4), (0.88, -2, 6)
            ]
            for item in yOffsets {
                var road = Path()
                let y = size.height * item.frac
                road.move(to: CGPoint(x: 0, y: y))
                road.addQuadCurve(
                    to: CGPoint(x: size.width, y: y + item.endOff),
                    control: CGPoint(x: size.width * 0.5, y: y + item.ctrlOff))
                context.stroke(road, with: .color(roadColor), style: style)
            }

            // Vertical "roads"
            let xOffsets: [(frac: Double, endOff: CGFloat, ctrlOff: CGFloat)] = [
                (0.2, 5, -7), (0.5, -4, 6), (0.78, 3, -5)
            ]
            for item in xOffsets {
                var road = Path()
                let x = size.width * item.frac
                road.move(to: CGPoint(x: x, y: 0))
                road.addQuadCurve(
                    to: CGPoint(x: x + item.endOff, y: size.height),
                    control: CGPoint(x: x + item.ctrlOff, y: size.height * 0.5))
                context.stroke(road, with: .color(roadColor), style: style)
            }

            // Diagonal road
            var diag = Path()
            diag.move(to: CGPoint(x: 0, y: size.height * 0.15))
            diag.addLine(to: CGPoint(x: size.width * 0.7, y: size.height))
            context.stroke(diag, with: .color(roadColor), style: style)
        }
        .clipShape(RoundedRectangle(cornerRadius: 23))
    }

    /// Value only (used for primary stat where unit is shown separately)
    private func mockValue(_ type: MapStatType) -> String {
        switch type {
        case .speed: return "18.4"
        case .averageSpeed: return "16.2"
        case .heartRate: return "142"
        case .distance: return "12.3"
        case .movingTime: return "0:47:12"
        case .elapsedTime: return "0:52:30"
        case .elevation: return "847"
        case .grade: return "3.2%"
        case .power: return "185"
        case .distanceRemaining: return "8.1"
        case .calories: return "412"
        case .none: return ""
        }
    }

    /// Unit label for primary stat
    private func mockUnit(_ type: MapStatType) -> String {
        switch type {
        case .speed, .averageSpeed: return "mph"
        case .heartRate: return "bpm"
        case .calories: return "cal"
        case .power: return "W"
        case .distance, .distanceRemaining: return "mi"
        case .elevation: return "ft"
        default: return ""
        }
    }

    /// Value with unit inline (used for secondary stats)
    private func mockDisplayValue(_ type: MapStatType) -> String {
        switch type {
        case .speed: return "18.4 mph"
        case .averageSpeed: return "16.2 mph"
        case .heartRate: return "142 bpm"
        case .distance: return "12.3 mi"
        case .movingTime: return "0:47:12"
        case .elapsedTime: return "0:52:30"
        case .elevation: return "847 ft"
        case .grade: return "3.2%"
        case .power: return "185 W"
        case .distanceRemaining: return "8.1 mi"
        case .calories: return "412 cal"
        case .none: return ""
        }
    }
}

// MARK: - Map Config Import Sheet

struct MapConfigImportSheet: View {
    let configs: [(profileName: String, config: MapScreenConfig)]
    let onImport: (MapScreenConfig) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    ForEach(Array(configs.enumerated()), id: \.offset) { _, item in
                        Button {
                            onImport(item.config)
                            dismiss()
                        } label: {
                            VStack(spacing: 8) {
                                MapScreenPreview(config: item.config)

                                Text(item.profileName)
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)

                                configSummary(item.config)
                            }
                            .padding()
                            .background(.ultraThinMaterial)
                            .clipShape(RoundedRectangle(cornerRadius: 16))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding()
            }
            .navigationTitle("Import Map Config")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
    }

    @ViewBuilder
    private func configSummary(_ config: MapScreenConfig) -> some View {
        let parts = [
            config.primaryStat.label,
            "\(config.secondaryStats.filter { $0 != .none }.count) secondary",
            config.routeAheadColor.label + " route",
            "\(Int(config.defaultZoom))m zoom"
        ]
        Text(parts.joined(separator: " · "))
            .font(.caption)
            .foregroundStyle(.secondary)
    }
}

// MARK: - Preview

#Preview("Map Customization") {
    NavigationStack {
        MapCustomizationView(userSettings: {
            let store = UserSettingsStore()
            return store
        }())
    }
    .preferredColorScheme(.dark)
}

#Preview("Map Preview — Default") {
    MapScreenPreview(config: .default)
        .padding()
        .background(Color(white: 0.12))
        .preferredColorScheme(.dark)
}

#Preview("Map Preview — Minimal") {
    MapScreenPreview(config: MapScreenConfig(
        primaryStat: .speed,
        secondaryStats: [],
        showTurnInfo: false,
        showFullRouteToggle: false,
        showHeading: false,
        routeAheadColor: .cyan
    ))
    .padding()
    .background(Color(white: 0.12))
    .preferredColorScheme(.dark)
}

#Preview("Map Preview — Full") {
    MapScreenPreview(config: MapScreenConfig(
        primaryStat: .heartRate,
        secondaryStats: [.speed, .distance, .elevation, .movingTime],
        showTurnInfo: true,
        showFullRouteToggle: true,
        showHeading: true,
        routeAheadColor: .yellow
    ))
    .padding()
    .background(Color(white: 0.12))
    .preferredColorScheme(.dark)
}
