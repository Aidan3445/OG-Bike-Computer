//
//  WorkoutManager+Elevation.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// GPS sets the absolute elevation. The barometer books climbing when the
/// watch has one, and the elevation follows it between fixes.
extension WorkoutManager {
    func startAltimeter() {
        guard AltimeterReader.isAvailable, !altimeter.isRunning else { return }
        elevationTracker.barometer.reset()
        altimeter.start(
            onReading: { [weak self] reading, timestamp in
                self?.handleBarometerReading(reading, at: timestamp)
            },
            onAbsolute: { [weak self] data in
                self?.traceAbsoluteAltitude(data)
            })
    }

    func stopAltimeter() {
        altimeter.stop()
    }

    /// Climbing comes from GPS only with no barometer, or in a sim, where the
    /// climbing is in the track.
    func updateGPSElevation(_ location: CLLocation) {
        guard location.verticalAccuracy >= 0, location.verticalAccuracy < 20 else { return }
        let altitude = location.altitude
        currentElevation = altitude
        if altitude > highestElevation { highestElevation = altitude }
        if altitude < lowestElevation { lowestElevation = altitude }

        guard !AltimeterReader.isAvailable || isSimulating, location.verticalAccuracy < 10
        else { return }
        let change = elevationTracker.gpsChange(
            altitude: altitude, minDelta: ridePreferences.elevationSmoothing.elevMinDelta)
        if change > 0 {
            liveElevationGain += change
        } else if change < 0 {
            liveElevationLoss -= change
        }
    }

    private func handleBarometerReading(_ relativeAltitude: Double, at timestamp: TimeInterval) {
        let reference = elevationTracker.barometer.reference
        let gainBefore = elevationTracker.baroGain
        let lossBefore = elevationTracker.baroLoss
        var skipReason: String?
        defer {
            traceBarometer(
                relativeAltitude: relativeAltitude, reference: reference,
                skipReason: skipReason,
                gainBooked: elevationTracker.baroGain - gainBefore,
                lossBooked: elevationTracker.baroLoss - lossBefore,
                sensorTime: timestamp)
        }

        // Paused or not riding, the filter follows the readings so the drift
        // in between isn't booked on resume.
        guard isActive, !isPaused, autoPauseState == .moving else {
            skipReason = !isActive ? "inactive" : isPaused ? "paused" : "autoPause"
            elevationTracker.barometer.hold(relativeAltitude, at: timestamp)
            return
        }

        // Standing still books nothing, but a real change made meanwhile
        // (stairs, a curb) books once moving again.
        let waiting = departureDetector.isWaiting
        if waiting || isStandingStill {
            let jumpReason = elevationTracker.barometer.freeze(relativeAltitude, at: timestamp)
            let label = waiting ? "waiting" : "stationary"
            skipReason = jumpReason.map { "\(label)-\($0)" } ?? label
            return
        }

        // Below riding pace the barometer mostly sees walking and stairs, so
        // it books nothing until riding again, then books the net change.
        if !isSimulating, !isRecordingEverything, !stopDetector.isAtRidingSpeed {
            let jumpReason = elevationTracker.barometer.freeze(relativeAltitude, at: timestamp)
            skipReason = jumpReason.map { "slow-\($0)" } ?? "slow"
            return
        }

        switch elevationTracker.ingestBarometer(relativeAltitude, at: timestamp) {
        case .skipped(let reason):
            skipReason = reason
        case .gain(let climb):
            // A sim's climbing comes from its track. This only feeds the trace.
            guard !isSimulating else { return }
            liveElevationGain = elevationTracker.baroGain
            currentElevation += climb
            if currentElevation > highestElevation { highestElevation = currentElevation }
        case .loss(let drop):
            guard !isSimulating else { return }
            liveElevationLoss = elevationTracker.baroLoss
            currentElevation -= drop
            if currentElevation < lowestElevation { lowestElevation = currentElevation }
        }
    }
}
