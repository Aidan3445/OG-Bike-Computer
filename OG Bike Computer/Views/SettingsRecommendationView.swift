//
//  SettingsRecommendationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/15/26.
//

import SwiftUI
import UIKit

struct SettingsRecommendationView: View {
    var onContinue: (() -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                // Title
                Text("Welcome to Computa")
                    .font(.title2.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)

                Text("A couple of tips before your first ride.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                // MARK: - Watch settings
                VStack(alignment: .leading, spacing: 8) {
                    Label("Keep Computa visible on the watch", systemImage: "applewatch")
                        .font(.subheadline.weight(.semibold))

                    if let windowSize = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                        Image("settingsRec")
                            .resizable()
                            .frame(width: windowSize.screen.bounds.width / 2.5,
                                   height: windowSize.screen.bounds.height / 2.5)
                            .aspectRatio(contentMode: .fit)
                            .clipShape(.rect(cornerRadius: 24))
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(.secondary, lineWidth: 2)
                            }
                            .frame(maxWidth: .infinity)
                    } else {
                        Image("settingsRec")
                            .resizable()
                            .scaledToFit()
                            .cornerRadius(24)
                            .overlay {
                                RoundedRectangle(cornerRadius: 24)
                                    .stroke(.secondary, lineWidth: 2)
                            }
                    }

                    Text("Watch App → General → Return to Clock → Computa")
                        .font(.footnote)
                        .foregroundStyle(.secondary)

                    Text("Set:")
                        .font(.subheadline)
                        .padding(.top, 2)

                    VStack(alignment: .leading, spacing: 2) {
                        Text("• Custom: After 2 minutes or 1 hour")
                        Text("• When in Session: Return to App")
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)

                    Button {
                        openWatchApp()
                    } label: {
                        Text("Open Watch Settings")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .padding(.top, 4)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                // MARK: - Feature highlights
                VStack(alignment: .leading, spacing: 12) {
                    Label("New here? A few things to try", systemImage: "sparkles")
                        .font(.subheadline.weight(.semibold))

                    TipRow(
                        icon: "arrow.triangle.turn.up.right.diamond",
                        color: .cyan,
                        title: "Cue Editor",
                        detail: "Add, edit, or skip turns on any imported route before you ride."
                    )
                    TipRow(
                        icon: "square.stack.3d.up",
                        color: .indigo,
                        title: "Multi-Ride Viewer",
                        detail: "Stack several rides into one map and stats summary — great for tours and bikepacking trips."
                    )
                    TipRow(
                        icon: "slider.horizontal.3",
                        color: .purple,
                        title: "Settings update live",
                        detail: "Change anything — metrics, alerts, layouts — and it takes effect mid-ride. No restart needed."
                    )
                    TipRow(
                        icon: "waveform",
                        color: .red,
                        title: "Siri & Shortcuts",
                        detail: "Start, pause, or end a ride hands-free, and automate ride actions with the Shortcuts app."
                    )

                    Text("Find these and more in Settings → Tips.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 2)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                // Continue button (optional)
                if let onContinue {
                    Button("Continue") {
                        onContinue()
                    }
                    .foregroundStyle(.accent)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
    }

    private func openWatchApp() {
        guard let url = URL(string: "itms-watchs://") else { return }

        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
