//
//  StartRideView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import SwiftUI
import WatchKit

struct StartRideView: View {
    let route: Route?
    @ObservedObject var workout: WorkoutManager
    @ObservedObject private var unitState = UnitState.shared

    @ObservedObject var rideStore: RideStore
    @State private var isLoading = false
    @State private var extendedSession: WKExtendedRuntimeSession?
    @State private var pendingActivity: ActivityType?

    var body: some View {
        let _ = unitState.preferences
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
        .alert("Discard Held Ride?", isPresented: Binding(
            get: { pendingActivity != nil },
            set: { if !$0 { pendingActivity = nil } }
        )) {
            Button("Discard & Start", role: .destructive) {
                if let activity = pendingActivity {
                    pendingActivity = nil
                    doStartRide(activity: activity)
                }
            }
            Button("Cancel", role: .cancel) { pendingActivity = nil }
        } message: {
            Text("Starting a new ride will discard your held ride. This cannot be undone.")
        }
        .onAppear {
            let session = WKExtendedRuntimeSession()
            session.start()
            extendedSession = session
        }
        .onDisappear {
            extendedSession?.invalidate()
            extendedSession = nil
        }
    }

    private func startRide(activity: ActivityType) {
        if rideStore.heldRide != nil {
            pendingActivity = activity
        } else {
            doStartRide(activity: activity)
        }
    }

    private func doStartRide(activity: ActivityType) {
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
