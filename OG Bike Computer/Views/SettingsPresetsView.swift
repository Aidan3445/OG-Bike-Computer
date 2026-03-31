//
//  SettingsPresetsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/30/26.
//

import SwiftUI

struct SettingsPresetsView: View {
    @ObservedObject var userSettings: UserSettingsStore
    @State private var showCreateSheet = false
    @State private var showRenameAlert = false
    @State private var newProfileName = ""
    @State private var renameTargetID: UUID?
    @State private var createFromDefaults = false

    var body: some View {
        List {
            Section {
                ForEach(userSettings.presets) { preset in
                    let isActive = userSettings.activePresetID == preset.id

                    Button {
                        userSettings.switchToProfile(id: preset.id)
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: isActive ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(isActive ? .green : .secondary)
                                .font(.title3)

                            Text(preset.name)
                                .font(.body)
                                .foregroundStyle(.primary)

                            Spacer()

                            if isActive {
                                Text("Active")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.green)
                                    .padding(.horizontal, 6)
                                    .padding(.vertical, 2)
                                    .background(.green.opacity(0.15))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                    .contextMenu {
                        Button {
                            newProfileName = preset.name
                            renameTargetID = preset.id
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }

                        if userSettings.presets.count > 1 {
                            Button(role: .destructive) {
                                userSettings.deletePreset(id: preset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                    }
                    .swipeActions(edge: .trailing) {
                        if userSettings.presets.count > 1 {
                            Button(role: .destructive) {
                                userSettings.deletePreset(id: preset.id)
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }

                        Button {
                            newProfileName = preset.name
                            renameTargetID = preset.id
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("Profiles")
            } footer: {
                Text("Tap to switch profiles. Settings changes are saved automatically to the active profile. Long-press or swipe for more options.")
            }

            Section {
                Button {
                    createFromDefaults = false
                    newProfileName = ""
                    showCreateSheet = true
                } label: {
                    Label("New from Current Settings", systemImage: "doc.on.doc")
                }
                .disabled(userSettings.presets.count >= UserSettingsStore.maxPresets)

                Button {
                    createFromDefaults = true
                    newProfileName = ""
                    showCreateSheet = true
                } label: {
                    Label("New from Defaults", systemImage: "plus.circle")
                }
                .disabled(userSettings.presets.count >= UserSettingsStore.maxPresets)
            } footer: {
                Text("Up to \(UserSettingsStore.maxPresets) profiles. Rider profiles (weight, height, bikes) are shared across all settings profiles.")
            }
        }
        .navigationTitle("Profiles")
        .alert("New Profile", isPresented: $showCreateSheet) {
            TextField("Profile name", text: $newProfileName)
            Button("Create") {
                let name = newProfileName.isEmpty ? "Profile \(userSettings.presets.count + 1)" : newProfileName
                if createFromDefaults {
                    _ = userSettings.createFromDefaults(name: name)
                } else {
                    _ = userSettings.createFromCurrent(name: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Profile", isPresented: $showRenameAlert) {
            TextField("New name", text: $newProfileName)
            Button("Rename") {
                if let id = renameTargetID {
                    userSettings.renamePreset(id: id, name: newProfileName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
