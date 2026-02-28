//
//  StartRideView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI

struct StartRideView: View {
    let route: Route
    @ObservedObject var workout: WorkoutManager

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                Text(route.name)
                    .font(.headline)
                    .multilineTextAlignment(.center)

                Text(formatDistance(route.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Divider()

                ForEach(ActivityType.allCases) { activity in
                    Button {
                        workout.start(activity: activity)
                    } label: {
                        Label(activity.name, systemImage: activity.icon)
                            .frame(maxWidth: .infinity)
                    }
                    .tint(activity == .cycling ? .green : .blue)
                }
            }
            .padding()
        }
        .navigationTitle("Start")
        .navigationBarTitleDisplayMode(.inline)
    }
}
