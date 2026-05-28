//
//  TipsView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/15/26.
//

import Foundation

import SwiftUI

struct TipsView: View {
    var body: some View {
        List {
            NavigationLink {
                SettingsRecommendationView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Watch Settings")
                        Text("Keep watch app open before and during a ride.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "exclamationmark.applewatch")
                        .foregroundStyle(.green)
                }
            }

            NavigationLink {
                LiveSettingsTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Live Settings")
                        Text("All settings update instantly, even mid-ride.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.purple)
                }
            }

            NavigationLink {
                RouteImportTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Importing Routes")
                        Text("How to get routes from Strava and RideWithGPS.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.down.doc")
                        .foregroundStyle(.blue)
                }
            }

            NavigationLink {
                RouteSourcesTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Route Sources & Navigation")
                        Text("How your route source affects turn-by-turn accuracy.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "location.north.line")
                        .foregroundStyle(.orange)
                }
            }

            NavigationLink {
                CueEditorTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Cue Editor")
                        Text("Add, edit, or skip turns on any imported route.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "arrow.triangle.turn.up.right.diamond")
                        .foregroundStyle(.cyan)
                }
            }

            NavigationLink {
                MultiRideTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Multi-Ride Viewer")
                        Text("Stack multiple rides into one map and stats summary.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "square.stack.3d.up")
                        .foregroundStyle(.indigo)
                }
            }

            NavigationLink {
                SiriShortcutsTipView()
            } label: {
                Label {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Siri, Shortcuts & Automations")
                        Text("Control rides hands-free and automate with the Shortcuts app.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "waveform")
                        .foregroundStyle(.red)
                }
            }
        }
        .navigationTitle("Tips")
    }
}
