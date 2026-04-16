//
//  SiriShortcutsTipView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/16/26.
//

import SwiftUI
import UIKit

struct SiriShortcutsTipView: View {
    private let exampleShortcutURL = URL(string: "https://www.icloud.com/shortcuts/d1064fd68107464984037b6db62f1523")!

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                // Header
                VStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.system(size: 48))
                        .foregroundStyle(.red)
                    Text("Siri, Shortcuts & Automations")
                        .font(.title2)
                        .bold()
                    Text("Computa works with Siri and the Shortcuts app so you can start, pause, and control rides hands-free or automatically.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Siri
                VStack(alignment: .leading, spacing: 10) {
                    Label("Siri", systemImage: "waveform")
                        .font(.headline)
                        .foregroundStyle(.pink)

                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(
                            icon: "bicycle",
                            color: .green,
                            title: "Start a ride",
                            detail: "\"Hey Siri, start a ride with Computa\" to begin a free ride recording instantly."
                        )
                        TipRow(
                            icon: "pause.fill",
                            color: .yellow,
                            title: "Pause & resume",
                            detail: "\"Pause my Computa ride\" or \"Resume my Computa ride\" to control recording without touching your phone."
                        )
                        TipRow(
                            icon: "stop.fill",
                            color: .red,
                            title: "End a ride",
                            detail: "\"End my Computa ride\" to finish and save your recording."
                        )
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                // Shortcuts app
                VStack(alignment: .leading, spacing: 10) {
                    Label("Shortcuts App", systemImage: "square.grid.2x2")
                        .font(.headline)
                        .foregroundStyle(.mint)

                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(
                            icon: "square.and.arrow.down",
                            color: .teal,
                            title: "Ready-made shortcut",
                            detail: "Download an example shortcut that starts a Computa ride, use it as a starting point for your own automations."
                        )
                        TipRow(
                            icon: "rectangle.on.rectangle",
                            color: .cyan,
                            title: "Action Button",
                            detail: "Assign a Computa shortcut to your iPhone's Action Button for one-press ride control."
                        )
                        TipRow(
                            icon: "bicycle.circle",
                            color: .blue,
                            title: "Combine with other actions",
                            detail: "Chain Computa actions with other apps. For example, start a ride and open a music playlist at the same time."
                        )
                    }

                    Button {
                        UIApplication.shared.open(exampleShortcutURL)
                    } label: {
                        Label("Get Example Shortcut", systemImage: "arrow.down.circle")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.accentColor)
                    .padding(.top, 4)
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                // Automations
                VStack(alignment: .leading, spacing: 10) {
                    Label("Automations", systemImage: "clock.arrow.2.circlepath")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    TipRow(
                        icon: "location.fill",
                        color: .pink,
                        title: "Location + time triggers",
                        detail: "Use the Shortcuts Automations tab to trigger a Computa action based on where you are and what time it is. For example: automatically start a free ride recording when you leave work between 4–6 PM."
                    )

                    // Two screenshots side by side
                    AutomationScreenshotRow()

                    TipRow(
                        icon: "figure.outdoor.cycle",
                        color: .purple,
                        title: "Never forget to record",
                        detail: "Set up a \"Leave location\" automation for your home, workplace, or gym so Computa starts recording as soon as you hop on the bike."
                    )
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("Siri & Shortcuts")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Automation Screenshots

private struct AutomationScreenshotRow: View {
    // Placeholder: both reference settingsRec until real screenshots are swapped in
    private let leftImage = "automation"
    private let rightImage = "shortcut"

    var body: some View {
        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let h = windowScene.screen.bounds.height / 2.5
            HStack(spacing: 12) {
                screenshotImage(leftImage, height: h)
                screenshotImage(rightImage, height: h)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 4)
        }
    }

    private func screenshotImage(_ name: String, height: CGFloat) -> some View {
        Image(name)
            .resizable()
            .aspectRatio(contentMode: .fit)
            .frame(height: height)
            .clipShape(RoundedRectangle(cornerRadius: 30))
            .overlay {
                RoundedRectangle(cornerRadius: 30)
                    .stroke(.secondary, lineWidth: 2)
            }
    }
}
