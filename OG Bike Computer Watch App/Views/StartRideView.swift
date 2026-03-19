//
//  StartRideView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct StartRideView: View {
    let route: Route?
    @ObservedObject var workout: WorkoutManager

    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                if isLoading {
                    Spacer()
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Processing route…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer()
                } else {
                    if let route {
                        Text(route.name)
                            .font(.headline)
                            .multilineTextAlignment(.center)
                        Text(formatDistance(route.distance))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Image(systemName: "record.circle")
                            .font(.system(size: 32))
                            .foregroundStyle(.orange)
                        Text("Free Ride")
                            .font(.headline)
                        Text("Record without navigation")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Divider()

                    ForEach(ActivityType.allCases) { activity in
                        Button {
                            startRide(activity: activity)
                        } label: {
                            Label(activity.name, systemImage: activity.icon)
                                .frame(maxWidth: .infinity)
                        }
                        .tint(activity == .cycling ? .green : .blue)
                    }
                }
            }
            .padding()
        }
        .navigationTitle("Start")
        .navigationBarTitleDisplayMode(.inline)
    }

    private func startRide(activity: ActivityType) {
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            if let route {
                workout.loadRoute(route)
            }
            DispatchQueue.main.async {
                workout.start(activity: activity)
            }
        }
    }
}
