//
//  LiveSettingsTipView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/16/26.
//

import SwiftUI

struct LiveSettingsTipView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "slider.horizontal.3")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                    .padding(.top, 8)

                Text("Settings Update Live")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Every setting in Computa takes effect instantly, even mid-ride! You should never need to stop or restart anything.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    TipRow(
                        icon: "gauge.with.dots.needle.bottom.50percent",
                        color: .blue,
                        title: "Swap metrics on the fly",
                        detail: "Don't like what you see on screen? Open settings and change displayed fields, they will update immediately."
                    )
                    TipRow(
                        icon: "bell.badge",
                        color: .orange,
                        title: "Adjust alerts anytime",
                        detail: "Turn heart rate zones, speed alerts, or interval cues on or off without interrupting your ride."
                    )
                    TipRow(
                        icon: "paintbrush",
                        color: .purple,
                        title: "Experiment freely",
                        detail: "Try different layouts and display options. There's no wrong answer, dial in what works best for you."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("Live Settings")
        .navigationBarTitleDisplayMode(.inline)
    }
}
