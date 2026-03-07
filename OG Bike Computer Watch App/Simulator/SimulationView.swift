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
    @State private var isLoading = false

    var body: some View {
        List {
            if isLoading {
                Section {
                    VStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(1.5)
                        Text("Processing route…")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
            } else {
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
                            startSimulation()
                        }
                        .tint(.green)
                    }
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

    private func startSimulation() {
        guard let route = selectedRoute else { return }
        isLoading = true
        DispatchQueue.global(qos: .userInitiated).async {
            workout.loadRoute(route)
            DispatchQueue.main.async {
                workout.startSimulation(activity: .cycling)
                simulator.attach(to: workout)
                simulator.play()
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
