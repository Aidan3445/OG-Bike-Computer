//
//  RideSimulator.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/6/26.
//

import Foundation
import CoreLocation
import Combine

class RideSimulator: ObservableObject {
    @Published var isPlaying = false
    @Published var progress: Double = 0
    @Published var currentPointIndex: Int = 0
    @Published var playbackSpeed: Double = 8

    private(set) var track: SimGPXLoader.SimTrack?
    private weak var workout: WorkoutManager?
    private var timer: Timer?

    let speedOptions: [Double] = [1, 2, 4, 8, 16, 32, 64]

    var pointCount: Int { track?.locations.count ?? 0 }
    var isLoaded: Bool { track != nil && pointCount >= 2 }
    var trackName: String { track?.name ?? "—" }

    func load(_ simTrack: SimGPXLoader.SimTrack) {
        track = simTrack
        currentPointIndex = 0
        progress = 0
        print("[Sim] Track loaded: \(simTrack.name), \(simTrack.locations.count) pts")
    }

    func attach(to workout: WorkoutManager) {
        self.workout = workout
    }

    func play() {
        guard let track = track, track.locations.count >= 2, let workout = workout else { return }
        isPlaying = true
        scheduleNext(track: track, workout: workout)
    }

    func pause() {
        isPlaying = false
        timer?.invalidate()
        timer = nil
    }

    func stop() {
        pause()
        currentPointIndex = 0
        progress = 0
    }

    func cycleSpeed() {
        guard let idx = speedOptions.firstIndex(of: playbackSpeed) else {
            playbackSpeed = speedOptions.first ?? 1
            return
        }
        playbackSpeed = speedOptions[(idx + 1) % speedOptions.count]

        if isPlaying {
            timer?.invalidate()
            timer = nil
            guard let track = track, let workout = workout else { return }
            scheduleNext(track: track, workout: workout)
        }
    }

    func seekTo(_ fraction: Double) {
        guard let track = track, let workout = workout else { return }
        let index = Int(fraction * Double(track.locations.count - 1))
        currentPointIndex = max(0, min(index, track.locations.count - 1))
        progress = fraction

        // Compute speed from neighboring points for a realistic location
        let loc = track.locations[currentPointIndex]
        let speed = computeSpeed(at: currentPointIndex, in: track.locations)
        let enriched = enrichLocation(loc, speed: speed, course: computeCourse(at: currentPointIndex, in: track.locations))
        workout.processLocation(enriched)
    }

    // Schedule the next point using real timestamp gaps scaled by playback speed
    private func scheduleNext(track: SimGPXLoader.SimTrack, workout: WorkoutManager) {
        guard isPlaying, currentPointIndex < track.locations.count else {
            if currentPointIndex >= track.locations.count {
                pause()
                print("[Sim] Playback complete")
            }
            return
        }

        let loc = track.locations[currentPointIndex]
        let speed = computeSpeed(at: currentPointIndex, in: track.locations)
        let course = computeCourse(at: currentPointIndex, in: track.locations)
        let enriched = enrichLocation(loc, speed: speed, course: course)
        workout.processLocation(enriched)

        let i = currentPointIndex
        currentPointIndex += 1
        progress = Double(currentPointIndex) / Double(track.locations.count)

        // Compute delay to next point
        if currentPointIndex < track.locations.count {
            let currentTS = track.locations[i].timestamp
            let nextTS = track.locations[currentPointIndex].timestamp
            var gap = nextTS.timeIntervalSince(currentTS) / playbackSpeed
            gap = max(0.01, min(gap, 5.0 / playbackSpeed)) // clamp crazy gaps

            timer = Timer.scheduledTimer(withTimeInterval: gap, repeats: false) { [weak self] _ in
                guard let self = self else { return }
                self.scheduleNext(track: track, workout: workout)
            }
        } else {
            pause()
            print("[Sim] Playback complete")
        }
    }

    private func computeSpeed(at index: Int, in locations: [CLLocation]) -> Double {
        guard index > 0 else {
            if locations.count > 1 {
                let dist = locations[1].distance(from: locations[0])
                let dt = locations[1].timestamp.timeIntervalSince(locations[0].timestamp)
                return dt > 0 ? dist / dt : 0
            }
            return 0
        }
        let prev = locations[index - 1]
        let curr = locations[index]
        let dist = curr.distance(from: prev)
        let dt = curr.timestamp.timeIntervalSince(prev.timestamp)
        return dt > 0 ? dist / dt : 0
    }

    private func computeCourse(at index: Int, in locations: [CLLocation]) -> Double {
        let next = index < locations.count - 1 ? index + 1 : index
        let prev = index > 0 ? index - 1 : index
        guard prev != next else { return -1 }
        let from = locations[prev].coordinate
        let to = locations[next].coordinate
        return RouteProcessor.bearing(from: from, to: to)
    }

    private func enrichLocation(_ loc: CLLocation, speed: Double, course: Double) -> CLLocation {
        CLLocation(
            coordinate: loc.coordinate,
            altitude: loc.altitude,
            horizontalAccuracy: 5,
            verticalAccuracy: 5,
            course: course,
            courseAccuracy: 10,
            speed: speed,
            speedAccuracy: 1,
            timestamp: Date())
    }
}
