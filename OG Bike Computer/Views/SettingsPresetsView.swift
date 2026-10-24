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
    @State private var newPresetName = ""
    @State private var renameTargetID: UUID?
    @State private var createFromDefaults = false

    var body: some View {
        List {
            Section {
                ForEach(userSettings.presets) { preset in
                    let isActive = userSettings.activePresetID == preset.id

                    Button {
                        userSettings.switchToPreset(id: preset.id)
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
                            newPresetName = preset.name
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
                            newPresetName = preset.name
                            renameTargetID = preset.id
                            showRenameAlert = true
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.orange)
                    }
                }
            } header: {
                Text("Presets")
            } footer: {
                Text("Tap to switch presets. Settings changes are saved automatically to the active preset. Long-press or swipe for more options.")
            }

            Section {
                Button {
                    createFromDefaults = false
                    newPresetName = ""
                    showCreateSheet = true
                } label: {
                    Label("New from Current Settings", systemImage: "doc.on.doc")
                }
                .disabled(userSettings.presets.count >= UserSettingsStore.maxPresets)

                Button {
                    createFromDefaults = true
                    newPresetName = ""
                    showCreateSheet = true
                } label: {
                    Label("New from Defaults", systemImage: "plus.circle")
                }
                .disabled(userSettings.presets.count >= UserSettingsStore.maxPresets)
            } footer: {
                Text("Up to \(UserSettingsStore.maxPresets) presets. Your Rider Profile (weight, bikes) is shared across all presets.")
            }
        }
        .navigationTitle("Presets")
        .alert("New Preset", isPresented: $showCreateSheet) {
            TextField("Preset name", text: $newPresetName)
            Button("Create") {
                let name = newPresetName.isEmpty ? "Preset \(userSettings.presets.count + 1)" : newPresetName
                if createFromDefaults {
                    _ = userSettings.createFromDefaults(name: name)
                } else {
                    _ = userSettings.createFromCurrent(name: name)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
        .alert("Rename Preset", isPresented: $showRenameAlert) {
            TextField("New name", text: $newPresetName)
            Button("Rename") {
                if let id = renameTargetID {
                    userSettings.renamePreset(id: id, name: newPresetName)
                }
            }
            Button("Cancel", role: .cancel) {}
        }
    }
}
