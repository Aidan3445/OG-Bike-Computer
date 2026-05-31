//
//  MileMarkerLabel.swift
//  OG Bike Computer
//
//  Two map annotation views used together on ride/route detail maps:
//
//  • `MileMarkerLabel` is a static capsule with the mile number — it never
//    rotates, so it does not observe the live camera state and is cheap to
//    render once and leave alone.
//
//  • `MileMarkerArrow` sits at a separate annotation halfway along the route
//    to the next marker (snapped to a track point) and is the only view that
//    counter-rotates against the camera. Because the label and the arrow no
//    longer share an annotation, a per-frame camera update only invalidates
//    the small arrow view instead of forcing the whole label/arrow HStack to
//    re-layout — which on-device was the source of mile-marker lag during
//    rotation.
//

import SwiftUI

struct MileMarkerLabel: View {
    let mile: Int
    let unitLabel: String

    var body: some View {
        Text("\(mile) \(unitLabel)")
            .font(.system(size: 10, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1)
            .background(Color.accentColor)
            .clipShape(Capsule())
    }
}

struct MileMarkerArrow: View {
    @ObservedObject var camera: MapCameraState
    /// World bearing of route travel at this arrow's location (0=N, 90=E).
    let worldBearing: Double

    var body: some View {
        Image(systemName: "arrow.up.circle.fill")
            .font(.system(size: 14))
            .foregroundStyle(.white, Color.accentColor)
            .rotationEffect(.degrees(worldBearing - camera.heading))
    }
}
