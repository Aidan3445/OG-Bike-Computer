//
//  PhoneAlertSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct PhoneAlertSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore
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
                Text("Live Activity")
            } footer: {
                Text("Shown on the Lock Screen and Dynamic Island whenever a ride is in progress. Pick the six stats that appear in the lock-screen grid. Safe to dismiss from the Lock Screen: your ride keeps recording on the watch.")
            }

            Section {
                Toggle("Turn Notifications", isOn: prefs.showTurnNotifications)
            } header: {
                Text("Phone Notifications")
            } footer: {
                Text("Also post a banner notification on the iPhone for each upcoming turn, in addition to the spoken alert. Requires a loaded route.")
            }

            if userSettings.settings.phoneAlerts != .default {
                Section {
                    Button("Reset to Defaults", role: .destructive) {
                        showResetConfirm = true
                    }
                }
            }
        }
        .settingsPageTitle("Live Activity", preset: userSettings.activePresetName)
        .confirmationDialog(
            "Reset Live Activity to Defaults?",
            isPresented: $showResetConfirm,
            titleVisibility: .visible
        ) {
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
