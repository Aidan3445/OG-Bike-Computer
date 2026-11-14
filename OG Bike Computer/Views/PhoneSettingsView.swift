//
//  PhoneSettingsView.swift
//  OG Bike Computer
//

import SwiftUI

/// UserDefaults keys for settings that only affect this phone. They stay out
/// of `UserSettings` so they never sync to the watch or save into presets.
enum PhoneSettingsKeys {
    static let gradeColors = "phoneGradeColors"
}

struct PhoneSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @AppStorage(PhoneSettingsKeys.gradeColors) private var gradeColors = true
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
    @AppStorage(PhoneSettingsKeys.gradeColors) private var gradeColors = true

    var body: some View {
        Section("Map") {
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
