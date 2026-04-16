//
//  RouteSourcesTipView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/16/26.
//

import SwiftUI

struct RouteSourcesTipView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "map.and.arrow.up")
                        .font(.system(size: 48))
                        .foregroundStyle(.accent)
                    Text("Route Sources & Navigation")
                        .font(.title2)
                        .bold()
                    Text("Where your route comes from determines how accurate turn-by-turn navigation will be.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // Best
                SectionCard(color: .green, header: "Best — Full Cue Sheet") {
                    TipRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "RideWithGPS in-app import",
                        detail: "Using the built-in RWGPS route selector automatically pulls in the cue sheet, giving you street names and precise turn points."
                    )
                    TipRow(
                        icon: "checkmark.seal.fill",
                        color: .green,
                        title: "GPX with embedded cues from RWGPS",
                        detail: "On the RWGPS website (not the mobile app), choose \"Embed cues as waypoints\" when exporting a GPX file. Importing that file gives you full turn-by-turn with street names."
                    )
                    TipRow(
                        icon: "pencil.and.ruler.fill",
                        color: .green,
                        title: "Use the RWGPS Route Tracing Tool",
                        detail: "Routes created with the tracing tool on RWGPS produce the best cue sheets. For planned rides, this is the recommended starting point."
                    )
                }

                // Limited
                SectionCard(color: .orange, header: "Limited — Estimated Turns") {
                    TipRow(
                        icon: "exclamationmark.triangle.fill",
                        color: .orange,
                        title: "Strava routes & third-party GPX files",
                        detail: "These formats do not embed cue sheets. Computa will analyze the route path and curvature to estimate turn points — but this is not guaranteed to be fully accurate and will not include street names."
                    )
                    TipRow(
                        icon: "doc.fill",
                        color: .orange,
                        title: "Plain GPX imports",
                        detail: "Exporting a standard GPX from any service and importing it manually will work for navigation, but cue sheet details are rarely preserved. Expect estimated turns without street names."
                    )
                }

                Text("For the most reliable experience, plan routes in RideWithGPS and import using the built-in selector or a cue-embedded GPX export.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 4)
            }
            .padding()
        }
        .navigationTitle("Route Sources")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Helpers

private struct SectionCard<Content: View>: View {
    let color: Color
    let header: String
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(header)
                .font(.headline)
                .foregroundStyle(color)
            content()
        }
        .padding()
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
    }
}
