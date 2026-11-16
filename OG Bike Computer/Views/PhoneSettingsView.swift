//
//  PhoneSettingsView.swift
//  OG Bike Computer
//

import SwiftUI
import MapKit

/// UserDefaults keys for settings that only affect this phone. They stay out
/// of `UserSettings` so they never sync to the watch or save into presets.
enum PhoneSettingsKeys {
    static let gradeColors = "phoneGradeColors"
    static let mapStyle = "phoneMapStyle"
    static let mileMarkers = "phoneMileMarkers"
    static let directionArrows = "phoneDirectionArrows"
}

/// Base map for every map on the phone.
enum PhoneMapStyle: String, CaseIterable, Identifiable {
    case standard, satellite, hybrid

    var id: String { rawValue }

    var label: String {
        switch self {
        case .standard:  return "Standard"
        case .satellite: return "Satellite"
        case .hybrid:    return "Hybrid"
        }
    }

    var icon: String {
        switch self {
        case .standard:  return "map"
        case .satellite: return "globe.americas"
        case .hybrid:    return "globe.americas.fill"
        }
    }

    var mapStyle: MapStyle {
        switch self {
        case .standard:  return .standard(elevation: .flat)
        case .satellite: return .imagery(elevation: .flat)
        case .hybrid:    return .hybrid(elevation: .flat)
        }
    }
}

struct PhoneSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @AppStorage(PhoneSettingsKeys.gradeColors) private var gradeColors = true
    @AppStorage(PhoneSettingsKeys.mapStyle) private var mapStyle = PhoneMapStyle.standard
    @AppStorage(PhoneSettingsKeys.mileMarkers) private var mileMarkers = true
    @AppStorage(PhoneSettingsKeys.directionArrows) private var directionArrows = true
    @AppStorage(RouteImportCoordinator.autoSendDefaultsKey) private var autoSendRoutesToWatch = false
    @State private var showResetConfirm = false

    private var prefs: Binding<PhoneAlertPreferences> {
        $userSettings.settings.phoneAlerts
    }

    var body: some View {
        Form {
            Section {
                NavigationLink {
                    LiveActivityCustomizationView(userSettings: userSettings)
                } label: {
                    HStack {
                        Text("Customize Stats")
                        Spacer()
                        Text(userSettings.settings.phoneAlerts.liveActivitySlots.prefix(3).map(\.metricType.label).joined(separator: ", "))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            } header: {
                Label("Live Activity", systemImage: "iphone.radiowaves.left.and.right")
            } footer: {
                Text("Shown on the Lock Screen and Dynamic Island whenever a ride is in progress. Pick the six stats that appear in the lock-screen grid. Safe to dismiss from the Lock Screen: your ride keeps recording on the watch.")
            }

            Section {
                Toggle("Turn Notifications", isOn: prefs.showTurnNotifications)
            } header: {
                Label("Notifications", systemImage: "bell")
            } footer: {
                Text("Also post a banner notification on the iPhone for each upcoming turn, in addition to the spoken alert. Requires a loaded route.")
            }

            Section {
                Picker("Map Style", selection: $mapStyle) {
                    ForEach(PhoneMapStyle.allCases) { style in
                        Text(style.label).tag(style)
                    }
                }
                Toggle(distanceMarkersLabel, isOn: $mileMarkers)
                Toggle("Direction Arrows", isOn: $directionArrows)
            } header: {
                Label("Maps", systemImage: "map")
            } footer: {
                Text("Map style applies to every map on this phone, including the ride screen. Mile markers and the arrows between them show on ride and route maps. All of these are also in the ⋯ menu on those screens.")
            }

            Section {
                Toggle("Grade Colors", isOn: $gradeColors)
            } header: {
                Label("Charts", systemImage: "chart.xyaxis.line")
            } footer: {
                Text("Colors the bottom of the elevation charts on ride and route screens by how steep each stretch is. Scrubbing shows the grade either way.")
            }

            Section {
                Toggle("Auto-Send to Watch", isOn: $autoSendRoutesToWatch)
            } header: {
                Label("Routes", systemImage: "point.topleft.down.to.point.bottomright.curvepath")
            } footer: {
                Text("Sends each imported route to the watch right away. Also in the Import menu on the Routes tab.")
            }

            if userSettings.settings.phoneAlerts != .default {
                Section {
                    Button("Reset Live Activity to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Phone", preset: userSettings.activePresetName)
        .alert("Reset Live Activity to Defaults?", isPresented: $showResetConfirm) {
            Button("Reset", role: .destructive) {
                userSettings.settings.phoneAlerts = .default
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Stat slots, fallback, Dynamic Island, and turn notifications will be restored to their defaults.")
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

/// The Map section of a map screen's ⋯ menu: quick phone display toggles,
/// plus a way into the full Phone settings page.
struct MapMenuSection: View {
    @Binding var showPhoneSettings: Bool
    /// Off for maps that don't draw mile markers, like multi-ride.
    var showsMarkerToggles = true
    @AppStorage(PhoneSettingsKeys.gradeColors) private var gradeColors = true
    @AppStorage(PhoneSettingsKeys.mapStyle) private var mapStyle = PhoneMapStyle.standard
    @AppStorage(PhoneSettingsKeys.mileMarkers) private var mileMarkers = true
    @AppStorage(PhoneSettingsKeys.directionArrows) private var directionArrows = true

    var body: some View {
        Section("Map") {
            Picker(selection: $mapStyle) {
                ForEach(PhoneMapStyle.allCases) { style in
                    Label(style.label, systemImage: style.icon).tag(style)
                }
            } label: {
                Label("Map Style", systemImage: mapStyle.icon)
            }
            .pickerStyle(.menu)
            if showsMarkerToggles {
                Toggle(isOn: $mileMarkers) {
                    Label(distanceMarkersLabel, systemImage: "signpost.right")
                }
                Toggle(isOn: $directionArrows) {
                    Label("Direction Arrows", systemImage: "location.north.line")
                }
            }
            Toggle(isOn: $gradeColors) {
                Label("Grade Colors", systemImage: "chart.xyaxis.line")
            }
            Button {
                showPhoneSettings = true
            } label: {
                Label("Phone Settings…", systemImage: "iphone")
            }
        }
    }
}

/// "Mile Markers" or "Kilometer Markers", following the distance unit.
var distanceMarkersLabel: String {
    currentUnits.distance == .miles ? "Mile Markers" : "Kilometer Markers"
}

extension View {
    /// The Phone settings page in a sheet with a Done button, opened from a
    /// map screen's ⋯ menu.
    func phoneSettingsSheet(isPresented: Binding<Bool>) -> some View {
        sheet(isPresented: isPresented) {
            NavigationStack {
                PhoneSettingsView(userSettings: .shared)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") { isPresented.wrappedValue = false }
                        }
                    }
            }
        }
    }
}
