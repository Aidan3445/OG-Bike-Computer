//
//  HighlightChevron.swift
//  OG Bike Computer
//
//  Tiny direction marker dropped at each end of the cue-editor highlight
//  overlay. White on a slight shadow, rotated to indicate travel direction
//  relative to the current (heading-locked) map orientation.
//

import SwiftUI

struct HighlightChevron: View {
    /// Rotation in degrees, clockwise, in screen coordinates.
    let rotation: Double

    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
            .rotationEffect(.degrees(rotation))
    }
}
