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
                Label("Phone alerts increase battery usage on both devices.", systemImage: "battery.25")
                    .font(.footnote)
                    .foregroundStyle(.orange)
            }

            Section {
                Picker("Mode", selection: prefs.mode) {
                    ForEach(PhoneAlertMode.allCases, id: \.self) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .pickerStyle(.segmented)

                if userSettings.settings.phoneAlerts.mode == .liveActivity {
                    Toggle("Show Map Preview", isOn: prefs.liveActivityShowMap)
                }
            } header: {
                Text("Phone Alert Mode")
            } footer: {
                switch userSettings.settings.phoneAlerts.mode {
                case .off:
                    Text("No alerts will be sent to your iPhone during rides.")
                case .liveActivity:
                    Text("Shows ride stats, turn directions, and optional map preview on your iPhone Lock Screen and Dynamic Island.")
                case .turnNotifications:
                    Text("Sends a single notification for each upcoming turn that updates in-place. Tapping opens the route map.")
                }
            }
        }
        .navigationTitle("Phone Alerts")
    }
}
