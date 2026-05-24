//
//  ElevationProfileView.swift
//  OG Bike Computer Watch App
//

import SwiftUI

struct ElevationProfileView: View {
    @ObservedObject var workout: WorkoutManager

    @State private var mode: ElevationDefaultTab = .full

    private var elevationConfig: ElevationScreenConfig {
        workout.ridePreferences.elevationScreen
    }

    private var route: ProcessedRoute? { workout.navigation.processedRoute }

    private var simplifiedSamples: [ElevationSample] {
        route?.simplifiedElevation ?? []
    }

    private var poisToShow: [RoutePOI] {
        guard workout.ridePreferences.mapScreen.waypointDisplay.showsOnElevation else { return [] }
        return route?.pois ?? []
    }

    var body: some View {
        if let route = route, !simplifiedSamples.isEmpty || route.points.contains(where: { $0.elevation != nil }) {
            ElevationChart(
                samples: simplifiedSamples,
                pois: poisToShow,
                currentDistance: workout.navigation.distanceAlongRoute,
                currentElevation: workout.currentElevation,
                liveGain: workout.liveElevationGain,
                config: elevationConfig,
                showWaypoints: workout.ridePreferences.mapScreen.waypointDisplay.showsOnElevation,
                mode: $mode
            )
            .padding(.horizontal, 8)
            .padding(.top, 4)
            .safeAreaPadding(.top)
            .onAppear {
                // Re-apply the default each time the screen becomes visible —
                // manual mode flips only persist within a single visit so the
                // setting acts like a real "default tab" rather than a one-time
                // initial selection.
                mode = elevationConfig.defaultTab
            }
            .onChange(of: elevationConfig.defaultTab) { _, newValue in
                mode = newValue
            }
        } else {
            VStack(spacing: 8) {
                Image(systemName: "mountain.2")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("No elevation data")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
