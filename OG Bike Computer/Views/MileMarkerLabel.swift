//
//  MileMarkerLabel.swift
//  OG Bike Computer
//
//  Shared annotation view for ride/route detail maps. The label itself stays
//  screen-upright (left→right) because MapKit annotations are not rotated by
//  the camera. The arrow sits to the right of the label in screen space, but
//  its icon rotates by (worldBearing − cameraHeading) so it always points in
//  the direction of route travel — pointing "north" when the route heads
//  north on the underlying map regardless of how the user has spun the camera.
//
//  Observes `MapCameraState` directly so per-frame camera updates re-render
//  only the labels themselves, not the entire Map body.
//

import SwiftUI

struct MileMarkerLabel: View {
    @ObservedObject var camera: MapCameraState
    let mile: Int
    let unitLabel: String
    /// World bearing of route travel at this marker (0 = N, 90 = E).
    let worldBearing: Double

    var body: some View {
        HStack(spacing: 3) {
            Text("\(mile) \(unitLabel)")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(.white)
                .padding(.horizontal, 4)
                .padding(.vertical, 1)
                .background(Color.accentColor)
                .clipShape(Capsule())

            Image(systemName: "arrow.up.circle.fill")
                .font(.system(size: 12))
                .foregroundStyle(.white, Color.accentColor)
                .rotationEffect(.degrees(worldBearing - camera.heading))
        }
    }
}
