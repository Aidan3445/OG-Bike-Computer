//
//  IntegrationsSettingsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI

struct IntegrationsSettingsView: View {
    @ObservedObject var integrationSettings: IntegrationSettingsStore
    @State private var isConnecting: IntegrationServiceID?
    @State private var connectionError: String?

    var body: some View {
        List {
            // MARK: - Duplicate Warning
            if integrationSettings.settings.totalAutoUploadCount >= 2 {
                Section {
                    Label {
                        Text("Multiple services are set to auto-upload. If any of these services are also connected to each other (e.g. Strava auto-syncs to Apple Fitness), you may end up with duplicate activities.")
                            .font(.footnote)
                    } icon: {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .foregroundStyle(.yellow)
                    }
                }
            }

            // MARK: - Apple Health
            Section {
                Toggle(isOn: $integrationSettings.settings.healthKitAutoUpload) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Auto-Upload Workouts")
                            Text("Save rides to Apple Health automatically")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "heart.fill")
                            .foregroundStyle(.red)
                    }
                }
                // TODO: Sync healthKitAutoUpload preference to watch via UserSettings
                // so WorkoutManager can conditionally discard the HKWorkout after recording.
                // Currently the toggle is stored but the watch always saves to HealthKit.
            } header: {
                Text("Apple Health")
            }

            // MARK: - Ride With GPS
            serviceSection(
                service: .rideWithGPS,
                supportsAutoUpload: false
            )

            // MARK: - Strava
            serviceSection(
                service: .strava,
                supportsAutoUpload: true
            )

            // MARK: - Strava Attribution
            if integrationSettings.settings.config(for: .strava).isConnected {
                Section {
                    HStack {
                        Spacer()
                        Text("Powered by Strava")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                    }
                }
            }
        }
        .navigationTitle("Integrations")
        .alert("Connection Error", isPresented: .init(
            get: { connectionError != nil },
            set: { if !$0 { connectionError = nil } }
        )) {
            Button("OK") { connectionError = nil }
        } message: {
            Text(connectionError ?? "")
        }
    }

    @ViewBuilder
    private func serviceSection(service: IntegrationServiceID, supportsAutoUpload: Bool) -> some View {
        let config = integrationSettings.settings.config(for: service)

        Section {
            // Connect / Disconnect
            if config.isConnected {
                Button(role: .destructive) {
                    integrationSettings.disconnect(service: service)
                } label: {
                    Label {
                        Text("Disconnect")
                    } icon: {
                        Image(systemName: "xmark.circle")
                            .foregroundStyle(.red)
                    }
                }
            } else {
                Button {
                    connect(service: service)
                } label: {
                    Label {
                        HStack {
                            Text("Connect Account")
                            Spacer()
                            if isConnecting == service {
                                ProgressView()
                            }
                        }
                    } icon: {
                        Image(systemName: "person.badge.plus")
                            .foregroundStyle(.blue)
                    }
                }
                .disabled(isConnecting != nil)
            }

            // Import Routes toggle
            if config.isConnected {
                Toggle(isOn: serviceBinding(service, keyPath: \.importRoutes)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Import Routes")
                            Text("Browse and import routes from \(service.displayName)")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "map")
                            .foregroundStyle(.green)
                    }
                }
            }

            // Auto-Upload toggle (Strava only)
            if config.isConnected && supportsAutoUpload {
                Toggle(isOn: serviceBinding(service, keyPath: \.autoUpload)) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Automatic Uploads")
                            Text("Upload rides to \(service.displayName) after recording")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    } icon: {
                        Image(systemName: "arrow.up.circle")
                            .foregroundStyle(.orange)
                    }
                }
            }
        } header: {
            Label {
                Text(service.displayName)
            } icon: {
                Image(service.iconAsset)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
        }
    }

    private func serviceBinding(_ service: IntegrationServiceID, keyPath: WritableKeyPath<IntegrationSettings.ServiceConfig, Bool>) -> Binding<Bool> {
        Binding(
            get: { integrationSettings.settings.config(for: service)[keyPath: keyPath] },
            set: { newValue in
                var config = integrationSettings.settings.config(for: service)
                config[keyPath: keyPath] = newValue
                integrationSettings.settings.setConfig(config, for: service)
            }
        )
    }

    private func connect(service: IntegrationServiceID) {
        isConnecting = service
        Task {
            do {
                switch service {
                case .rideWithGPS:
                    _ = try await OAuthManager.shared.authenticateRWGPS()
                case .strava:
                    _ = try await OAuthManager.shared.authenticateStrava()
                }

                await MainActor.run {
                    var config = integrationSettings.settings.config(for: service)
                    config.isConnected = true
                    config.importRoutes = true
                    integrationSettings.settings.setConfig(config, for: service)
                    isConnecting = nil
                }
            } catch {
                await MainActor.run {
                    connectionError = error.localizedDescription
                    isConnecting = nil
                }
            }
        }
    }
}
