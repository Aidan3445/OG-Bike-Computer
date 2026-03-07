//
//  SimulationView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/6/26.
//

import SwiftUI

struct SimulationView: View {
    @ObservedObject var store: RouteStore
    @ObservedObject var workout: WorkoutManager
    @ObservedObject var simulator: RideSimulator

    @State private var selectedRoute: Route?
    @State private var simTracks: [SimGPXLoader.SimTrack] = []
    @State private var selectedTrack: SimGPXLoader.SimTrack?

    var body: some View {
        List {
            Section("Nav Route") {
                if let route = selectedRoute {
                    HStack {
                        Text(route.name).font(.caption)
                        Spacer()
                        Button("Clear") { selectedRoute = nil }
                            .font(.caption2)
                    }
                } else {
                    ForEach(store.routes) { route in
                        Button(route.name) { selectedRoute = route }
                            .font(.caption)
                    }
                }
            }

            Section("Replay Track") {
                if let track = selectedTrack {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.name).font(.caption)
                            Text("\(track.locations.count) pts")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Button("Clear") { selectedTrack = nil }
                            .font(.caption2)
                    }
                } else if simTracks.isEmpty {
                    Text("No GPX files found in bundle")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(simTracks.indices, id: \.self) { i in
                        Button {
                            selectedTrack = simTracks[i]
                            simulator.load(simTracks[i])
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(simTracks[i].name).font(.caption)
                                Text("\(simTracks[i].locations.count) pts")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }

            if selectedRoute != nil && simulator.isLoaded {
                Section {
                    Button("Start Simulation") {
                        guard let route = selectedRoute else { return }
                        workout.loadRoute(route)
                        workout.startSimulation(activity: .cycling)
                        simulator.attach(to: workout)
                        simulator.play()
                    }
                    .tint(.green)
                }
            }
        }
        .navigationTitle("Simulate")
        .onAppear {
            if simTracks.isEmpty {
                simTracks = SimGPXLoader.loadAll()
            }
        }
    }
}

// Overlay shown during active simulation — wraps real WorkoutView with controls
struct SimPlaybackOverlay: View {
    @ObservedObject var simulator: RideSimulator
    @ObservedObject var workout: WorkoutManager

    var body: some View {
        WorkoutView(
            workout: workout,
            onStop: {
                simulator.stop()
                workout.stop(save: false)
            }
        ) {
            VStack(spacing: 12) {
                Text("SIMULATION")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.yellow)

                ProgressView(value: simulator.progress)

                HStack(spacing: 12) {
                    Button(simulator.isPlaying ? "⏸" : "▶") {
                        if simulator.isPlaying {
                            simulator.pause()
                        } else {
                            simulator.play()
                        }
                    }

                    Button("\(Int(simulator.playbackSpeed))×") {
                        simulator.cycleSpeed()
                    }
                    .font(.caption.monospaced())

                    Spacer()

                    Text("\(simulator.currentPointIndex)/\(simulator.pointCount)")
                        .font(.system(size: 10).monospaced())
                        .foregroundStyle(.secondary)
                }
            }
            .padding()
        }
    }
}
