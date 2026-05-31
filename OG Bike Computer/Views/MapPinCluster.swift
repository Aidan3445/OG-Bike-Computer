//
//  MapPinCluster.swift
//  OG Bike Computer
//
//  Stand-in pin shown on detail-view maps when several nearby annotations
//  collapse into a single cluster at zoomed-out levels — turn-dense or long
//  routes get expensive when every cue/POI renders separately, so we merge
//  them visually and let the user tap to zoom in and break the cluster apart.
//
//  The foreground icon is `arrow.down.left.arrow.up.right` (an "expand" glyph,
//  hinting that the cluster will fan out on zoom). One or two stacked discs
//  sit behind it as a paper-stack metaphor, scaled to how many items are
//  inside (≥2 → one disc behind, ≥4 → two discs behind).
//
//  Color is caller-controlled so cluster pins can match the underlying pin
//  style they're standing in for (e.g. indigo for cue turns, orange for
//  route-map POIs, purple for cue-editor waypoints).
//

import SwiftUI

struct MapPinCluster: View {
    let count: Int
    let color: Color

    var body: some View {
        let size: CGFloat = 18
        ZStack {
            // Back-most disc — only for clusters of 4+ items.
            if count >= 4 {
                Circle()
                    .fill(color.opacity(0.55))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.55), lineWidth: 1.2))
                    .offset(x: 5, y: -5)
            }
            // Middle disc — appears as soon as the cluster has more than one item.
            if count >= 2 {
                Circle()
                    .fill(color.opacity(0.75))
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1.4))
                    .offset(x: 2.5, y: -2.5)
            }
            // Front disc + glyph.
            ZStack {
                Circle()
                    .fill(color)
                    .frame(width: size, height: size)
                    .overlay(Circle().stroke(.white, lineWidth: 2))
                    .shadow(radius: 1)
                Image(systemName: "arrow.down.left.arrow.up.right")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        // Pad the frame to cover the offset stack so taps land on the whole
        // visual cluster, not just the front disc.
        .frame(width: size + 12, height: size + 12, alignment: .center)
    }
}
