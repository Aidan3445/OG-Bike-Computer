//
//  WorkoutManager+Hold.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import HealthKit

/// Holding a ride saves it as it stands so it can be continued later as
/// the same ride. Checkpoints leave a held ride behind after a crash.
extension WorkoutManager {
    enum HoldConflictResolution {
        case saveAndHold
        case discardAndHold
        case cancel
    }

    /// Holds the ride, or asks first through `pendingHoldConflict` when
    /// another ride is already held.
    func attemptHold() {
        guard isActive, !isSimulating else { return }
        if let existing = rideStore?.heldRide, existing.id != currentRideID {
            pendingHoldConflict = true
        } else {
            holdRide()
        }
    }

    /// Save finishes the held ride first, Discard drops it, Cancel leaves both alone.
    func resolveHoldConflict(_ resolution: HoldConflictResolution) {
        pendingHoldConflict = false
        guard let existing = rideStore?.heldRide else { return }
        switch resolution {
        case .saveAndHold:
            finalizeHeldRide(summary: existing)
            holdRide()
        case .discardAndHold:
            discardHeldRide(summary: existing)
            holdRide()
        case .cancel:
            break
        }
    }

    func holdRide() {
        guard isActive, !isSimulating else { return }

        // Readings during a hold can sit far off and snap back, so continuing
        // starts a fresh altimeter session. It also reopens the trace files.
        stopRideServices()
        settleTentativeResume()

        let rideID = currentRideID ?? UUID()
        let trackFilename = "\(rideID.uuidString).track"
        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(trackFilename)
        var summary = makeRideSummary(
            id: rideID, date: initialRideStartDate ?? workoutStartDate ?? Date(),
            trackFilename: trackFilename)
        summary.isOnHold = true
        summary.heldRouteID = activeRoute?.id
        summary.splitProgress = currentSplitProgress()

        do {
            try encodeTrack().write(to: trackURL, options: .atomic)
        } catch {
            print("[Hold] Failed to write track: \(error)")
            return
        }
        // The held ride is on disk and in RideStore before anything async
        // starts, so a crash from here on can't lose it.
        rideStore?.update(summary)
        TransferLedger.shared.recordTransfer(rideID: summary.id)
        completedRideSummary = makeWatchSummary(isHeld: true)

        stopNavigationAndMirroring()
        expectSessionStates([.stopped, .ended])
        stopClock()
        stopDisplayTimer()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        // The phone hears before the session ends.
        ConnectivityManager.shared.sendRideTerminalIntent("held")
        let endDate = Date()
        healthKit.end()

        // Each held segment saves to Fitness as its own workout.
        healthKit.endSegment(at: endDate) { [weak self] segment in
            segment.save(waitForRoute: false) { _ in
                DispatchQueue.main.async {
                    // The track is already in place, so sendRide skips the copy.
                    ConnectivityManager.shared.sendRide(summary: summary, trackURL: trackURL)
                    RideCheckpointStore.delete()
                    self?.cleanup()
                }
            }
        }
    }

    func continueHeldRide(summary: RideSummary, route: Route? = nil) {
        guard !isActive else { return }

        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(
            summary.trackFilename)
        guard let trackData = try? Data(contentsOf: trackURL) else {
            print("[Continue] Could not load track for held ride")
            return
        }

        // The route from when the ride was held, if the watch still has it.
        if let route {
            loadRoute(route)
        } else {
            clearRoute()
        }

        let points = TrackEncoder.decodeV5Full(trackData)
        let heartRates = points.compactMap { $0.heartRate > 0 ? $0.heartRate : nil }
        let powers = points.compactMap { $0.power > 0 ? $0.power : nil }

        continuationBase = summary
        initialRideStartDate = summary.date

        recordedLocations = points.map { pt in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon),
                altitude: pt.altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: Date(timeIntervalSince1970: pt.timestamp))
        }
        recordedHeartRates = points.map { $0.heartRate > 0 ? $0.heartRate : nil }
        recordedPowers = points.map { $0.power > 0 ? $0.power : nil }

        // Averages carry on over the whole ride.
        heartRateStat = RunningStat(sum: heartRates.reduce(0, +), count: heartRates.count)
        powerStat = RunningStat(sum: powers.reduce(0, +), count: powers.count)
        averageHeartRate = heartRateStat.average
        averagePower = powerStat.average

        totalDistance = summary.distance
        movingTime = summary.movingTime
        timerAccumulated = summary.elapsedTime
        liveElevationGain = summary.elevationGain
        liveElevationLoss = summary.elevationLoss
        maxSpeed = summary.maxSpeed ?? 0
        maxHeartRate = summary.maxHeartRate ?? 0
        maxPower = summary.maxPower ?? 0
        activeCalories = summary.calories
        caloriesBase = summary.calories
        heldSplitProgress = summary.splitProgress
        highestElevation = summary.highestElevation ?? -Double.greatestFiniteMagnitude
        lowestElevation = summary.lowestElevation ?? Double.greatestFiniteMagnitude

        // Same ID, so the final save replaces the held ride on the phone.
        currentRideID = summary.id
        lastCheckpointLocationCount = recordedLocations.count

        // Neither side shows the ride as on hold while it's running again.
        var resumed = summary
        resumed.isOnHold = nil
        rideStore?.update(resumed)
        ConnectivityManager.shared.sendRideContinued(rideID: summary.id)

        start(activity: summary.activityType)
    }

    func finalizeHeldRide(summary: RideSummary) {
        guard !isActive else { return }

        var completed = summary
        completed.isOnHold = nil
        completed.wasAutoFinalized = nil
        rideStore?.update(completed)

        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(
            summary.trackFilename)
        ConnectivityManager.shared.sendRide(summary: completed, trackURL: trackURL)
    }

    /// Keeps the ride on the watch marked discarded, so it can be brought back
    /// from ride history. TransferLedger deletes it after 7 days.
    func discardHeldRide(summary: RideSummary) {
        var discarded = summary
        discarded.isOnHold = nil
        discarded.wasDiscarded = true
        rideStore?.update(discarded)
        TransferLedger.shared.markDiscarded(rideID: summary.id)
        ConnectivityManager.shared.sendDiscardRide(rideID: summary.id)
        print("[Hold] Soft-discarded held ride: \(summary.name)")
    }

    // MARK: - Checkpoints

    func startCheckpointTimer() {
        checkpointTimer?.invalidate()
        guard let interval = ridePreferences.checkpointInterval.interval else { return }
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) {
            [weak self] _ in
            self?.saveCheckpoint()
        }
    }

    func stopCheckpointTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
    }

    /// Turns a checkpoint left by a crash into a held ride.
    func recoverCheckpointIfNeeded() {
        guard !isActive, RideCheckpointStore.exists else { return }
        print("[Checkpoint] Found checkpoint, attempting recovery...")

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self, let recovered = RideCheckpointStore.recover() else { return }
            ConnectivityManager.shared.sendRide(
                summary: recovered.summary, trackURL: recovered.trackURL)
            RideCheckpointStore.delete()

            DispatchQueue.main.async {
                self.recoveredRideSummary = recovered.summary
                print(
                    "[Checkpoint] Recovered ride: \(recovered.summary.name), \(recovered.summary.pointCount) points"
                )
            }
        }
    }

    /// Only while moving, and only when the track has grown since the last one.
    private func saveCheckpoint() {
        guard isActive, !isPaused, autoPauseState == .moving else { return }
        let count = recordedLocations.count
        guard count > lastCheckpointLocationCount, count > 0 else { return }

        let rideID = currentRideID ?? UUID()
        var summary = makeRideSummary(
            id: rideID, date: workoutStartDate ?? Date(),
            trackFilename: "\(rideID.uuidString).track")
        summary.splitProgress = currentSplitProgress()

        RideCheckpointStore.save(
            summary, locations: recordedLocations, heartRates: recordedHeartRates,
            powers: recordedPowers
        ) { [weak self] in
            self?.lastCheckpointLocationCount = count
        }
    }
}
