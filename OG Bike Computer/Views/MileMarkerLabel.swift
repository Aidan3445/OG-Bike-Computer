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
//  • `MileMarkerArrow` is a travel-direction arrow. Zoomed out it sits
//    halfway between mile markers; zoomed in it sits between turns. It's its
//    own annotation so a camera rotation only re-renders the small arrow,
//    not the label next to it.
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
