//
//  PhoneAlertSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import SwiftUI

struct PhoneAlertSettingsView: View {
    @ObservedObject var userSettings: UserSettingsStore

    private var prefs: Binding<PhoneAlertPreferences> {
        $userSettings.settings.phoneAlerts
    }

    var body: some View {
        Form {
            Section {
                Toggle("Turn Notifications", isOn: prefs.showTurnNotifications)
            } header: {
                Text("Notifications")
            } footer: {
                Text("Post a banner notification on the iPhone for each upcoming turn, in addition to the spoken alert. Requires a loaded route.")
            }

            Section {
                Toggle("Show Map Preview", isOn: prefs.liveActivityShowMap)

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
                Text("The Live Activity is shown on the Lock Screen and Dynamic Island whenever a ride is in progress. When a route is loaded, it also displays the next turn and an optional map preview.")
            }

            if userSettings.settings.phoneAlerts != .default {
                Section {
                    Button("Reset Phone Alerts to Defaults", role: .destructive) {
                        userSettings.settings.phoneAlerts = .default
                    }
                }
            }
        }
        .settingsPageTitle("Phone Alerts", profile: userSettings.activeProfileName)
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
