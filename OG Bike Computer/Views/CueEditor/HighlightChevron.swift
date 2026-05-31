//
//  HighlightChevron.swift
//  OG Bike Computer
//
//  Tiny direction marker dropped at each end of the cue-editor highlight
//  overlay. White on a slight shadow, rotated to indicate travel direction
//  in WORLD space — counter-rotates against the live camera heading so the
//  arrow stays aligned with the underlying route as the user spins the map.
//
//  Observes `MapCameraState` directly so per-frame camera updates don't have
//  to re-render the surrounding Map body.
//

import SwiftUI

struct HighlightChevron: View {
    @ObservedObject var camera: MapCameraState
    /// World bearing the arrow should point in (0 = north, 90 = east).
    let worldBearing: Double

    var body: some View {
        Image(systemName: "arrowtriangle.up.fill")
            .font(.system(size: 14, weight: .black))
            .foregroundStyle(.white.opacity(0.95))
            .shadow(color: .black.opacity(0.4), radius: 1.5, y: 0.5)
            .rotationEffect(.degrees(worldBearing - camera.heading))
    }
}
