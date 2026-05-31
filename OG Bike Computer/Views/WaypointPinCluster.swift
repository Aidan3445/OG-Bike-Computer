//
//  WaypointPinCluster.swift
//  OG Bike Computer
//
//  Cluster stand-in for the default route-map's waypoint pins. Keeps the
//  exact `WaypointPin` glyph on the front and adds 1–2 faded copies of the
//  same pin behind it to indicate how many waypoints are stacked into the
//  cluster (≥2 → one disc behind, ≥4 → two discs behind). Tapping zooms in
//  to fan the cluster out into individual pins.
//

import SwiftUI

struct WaypointPinCluster: View {
    let count: Int

    var body: some View {
        ZStack {
            if count >= 4 {
                WaypointPin()
                    .opacity(0.55)
                    .offset(x: 6, y: -6)
            }
            if count >= 2 {
                WaypointPin()
                    .opacity(0.8)
                    .offset(x: 3, y: -3)
            }
            WaypointPin()
        }
        // Pad the frame so the offset stack stays inside the tap target.
        .frame(width: 34, height: 34, alignment: .center)
    }
}
