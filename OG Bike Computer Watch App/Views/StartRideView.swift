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
    @ObservedObject private var unitState = UnitState.shared

    @State private var isLoading = false

    var body: some View {
        ScrollView {
            VStack(spacing: 10) {
                if isLoading {
                    Spacer(minLength: 40)
                    ProgressView()
                        .scaleEffect(1.5)
                    Text("Processing route…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.top, 8)
                    Spacer(minLength: 40)
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
                        .padding(.vertical, 2)

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
            .padding(.horizontal)
            .padding(.top, 4)
            .padding(.bottom, 16)
        }
        .scrollIndicators(.visible)
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
