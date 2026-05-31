//
//  CueEditorWaypointPinCluster.swift
//  OG Bike Computer
//
//  Cluster stand-in for cue-editor waypoint pins. Same flag-on-disc glyph as
//  `CueEditorWaypointPin`, with 1–2 faded copies behind to telegraph cluster
//  size (≥2 → one behind, ≥4 → two behind). Color follows the underlying
//  pins: blue when every clustered waypoint is user-added, purple otherwise.
//

import SwiftUI

struct CueEditorWaypointPinCluster: View {
    let count: Int
    /// True only when *every* clustered waypoint is user-added — a mixed
    /// cluster falls back to the imported (purple) color since the imported
    /// pins are the more common case.
    let isAllUserAdded: Bool

    var body: some View {
        ZStack {
            if count >= 4 {
                CueEditorWaypointPin(isSelected: false, isUserAdded: isAllUserAdded)
                    .opacity(0.55)
                    .offset(x: 5, y: -5)
            }
            if count >= 2 {
                CueEditorWaypointPin(isSelected: false, isUserAdded: isAllUserAdded)
                    .opacity(0.8)
                    .offset(x: 2.5, y: -2.5)
            }
            CueEditorWaypointPin(isSelected: false, isUserAdded: isAllUserAdded)
        }
        // Pad the frame so the offset stack stays inside the tap target.
        .frame(width: 28, height: 28, alignment: .center)
    }
}
