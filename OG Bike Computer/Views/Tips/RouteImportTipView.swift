//
//  RouteImportTipView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/16/26.
//

import SwiftUI
import UIKit

struct RouteImportTipView: View {
    // Placeholder image names — replace with real screenshots later
    private let stravaImages: [String] = []
    private let rwgpsImages: [String] = []

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "arrow.down.doc")
                        .font(.system(size: 48))
                        .foregroundStyle(.blue)
                    Text("Importing Routes")
                        .font(.title2)
                        .bold()
                    Text("Routes can be imported from Strava, RWGPS, or a GPX file. Each service has a few different ways to get routes into the app.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // MARK: Strava
                VStack(alignment: .leading, spacing: 10) {
                    Label("Strava", systemImage: "bolt.fill")
                        .font(.headline)
                        .foregroundStyle(.orange)

                    if !stravaImages.isEmpty {
                        ScreenshotCarousel(imageNames: stravaImages)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(
                            icon: "globe",
                            color: .orange,
                            title: "Public routes only",
                            detail: "Only routes marked public appear in the route list. Even routes you created yourself will not appear if they're set to private. This is a limitation of the Strava API."
                        )
                        TipRow(
                            icon: "link",
                            color: .orange,
                            title: "Paste a public route URL",
                            detail: "Tap the + button in the top right to paste a link to any public Strava route without needing to save it first."
                        )
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))

                // MARK: RideWithGPS
                VStack(alignment: .leading, spacing: 10) {
                    Label("RideWithGPS", systemImage: "map.fill")
                        .font(.headline)
                        .foregroundStyle(.green)

                    if !rwgpsImages.isEmpty {
                        ScreenshotCarousel(imageNames: rwgpsImages)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        TipRow(
                            icon: "list.bullet",
                            color: .green,
                            title: "All your routes, plus collections",
                            detail: "Every route you've created shows up in the list. Collections (which can include routes from other users) are listed separately."
                        )
                        TipRow(
                            icon: "pin.fill",
                            color: .green,
                            title: "Quickest way: Pinned collection",
                            detail: "Add a route to your Pinned collection on RideWithGPS and it will appear at the top of the collections list in app."
                        )
                        TipRow(
                            icon: "link",
                            color: .green,
                            title: "Paste a route URL",
                            detail: "Copy a route URL from the RWGPS website or app and tap + to import it directly."
                        )
                        TipRow(
                            icon: "lock.open.fill",
                            color: .green,
                            title: "Private routes are available",
                            detail: "Unlike Strava, your private RWGPS routes still appear in the route list."
                        )
                    }
                }
                .padding()
                .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            }
            .padding()
        }
        .navigationTitle("Importing Routes")
        .navigationBarTitleDisplayMode(.inline)
    }
}

// MARK: - Screenshot Carousel

private struct ScreenshotCarousel: View {
    let imageNames: [String]

    var body: some View {
        if let windowSize = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            let w = windowSize.screen.bounds.width / 2.5
            let h = windowSize.screen.bounds.height / 2.5
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(imageNames, id: \.self) { name in
                        Image(name)
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: w, height: h)
                            .clipShape(RoundedRectangle(cornerRadius: 30))
                            .overlay {
                                RoundedRectangle(cornerRadius: 30)
                                    .stroke(.secondary, lineWidth: 2)
                            }
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }
}
