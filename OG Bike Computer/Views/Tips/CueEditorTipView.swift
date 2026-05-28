//
//  CueEditorTipView.swift
//  OG Bike Computer
//

import SwiftUI

struct CueEditorTipView: View {
    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond")
                    .font(.system(size: 48))
                    .foregroundStyle(.accent)
                    .padding(.top, 8)

                Text("Cue Editor")
                    .font(.title2)
                    .bold()
                    .multilineTextAlignment(.center)

                Text("Tweak any imported route's cue sheet before you ride. Add missing turns, fix bad ones, or skip turns you don't need announced.")
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                VStack(alignment: .leading, spacing: 12) {
                    TipRow(
                        icon: "plus.circle",
                        color: .blue,
                        title: "Add a missing turn",
                        detail: "Tap a spot along the route to drop a new cue. Pick a direction, optionally add a street name, and it'll be announced just like the imported ones."
                    )
                    TipRow(
                        icon: "pencil",
                        color: .orange,
                        title: "Edit an existing cue",
                        detail: "Tap a cue to change its direction, distance, or label. Useful when an imported route has the wrong turn direction or names a road weirdly."
                    )
                    TipRow(
                        icon: "eye.slash",
                        color: .gray,
                        title: "Skip cues you don't need",
                        detail: "Hide cues you don't want spoken (e.g. driveways, gentle bends that aren't real turns). The route still tracks the same — just no voice prompt."
                    )
                    TipRow(
                        icon: "checkmark.seal",
                        color: .green,
                        title: "Saved per route",
                        detail: "Edits are saved to the route and synced to the watch the next time you send it. Re-import the route any time to start fresh."
                    )
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.top, 4)
            }
            .padding()
        }
        .navigationTitle("Cue Editor")
        .navigationBarTitleDisplayMode(.inline)
    }
}
