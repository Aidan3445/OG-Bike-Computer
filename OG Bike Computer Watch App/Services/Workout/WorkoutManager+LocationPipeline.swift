//
//  WorkoutManager+LocationPipeline.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Every GPS fix goes through `processLocation`: metrics, navigation, the
/// departure wait, auto-pause, then distance and the saved track.
extension WorkoutManager {
    func processLocation(_ location: CLLocation) {
        let receivedAt = Date()
        DispatchQueue.main.async {
            let previousFix = self.currentLocation
            let stateBefore = self.autoPauseState
            let distanceBefore = self.totalDistance
            let gapPending = self.distanceTracker.skipsNextGap
            var recorded = false
            var gpsMode: BatteryManager.GPSMode?
            defer {
                self.traceFix(
                    location, receivedAt: receivedAt, previousFix: previousFix,
                    stateBefore: stateBefore, recorded: recorded,
                    distanceAdded: self.totalDistance - distanceBefore,
                    gapSkipped: gapPending && !self.distanceTracker.skipsNextGap,
                    gpsMode: gpsMode)
            }
            self.currentLocation = location
            self.lastLocationUpdateAt = Date()
            self.positionBuffer.append(location)

            // A speed with no accuracy is stale. While auto-paused it reads 0
            // so a stuck reading can't show on screen or start a resume.
            self.speed =
                location.speedAccuracy < 0 || self.isAutoPaused ? 0 : max(location.speed, 0)

            self.updateExtendedMetrics(location)
            if self.hasRoute {
                self.updateNavigation(location)
            }

            // Sim rides skip auto-pause and never save. They still record
            // locations so the map has a trail to draw.
            if self.isSimulating {
                self.accumulateDistance(location)
                self.checkSplit()
                self.recordedLocations.append(location)
                self.simulateBodyMetrics(location, previousFix: previousFix)
                return
            }

            self.stopDetector.noteFix(location)
            if self.departureDetector.isWaiting {
                self.awaitDeparture(location)
            }
            self.updateAutoPause()
            // Auto-pause may have just paused.
            if self.isAutoPaused {
                self.speed = 0
            }

            switch self.autoPauseState {
            case .moving:
                guard !self.departureDetector.isWaiting, !self.holdForStop(location) else { break }
                self.accumulateDistance(location)
                self.checkSplit()
                // Stops leave no track, so the map shows no scribble at a store.
                guard !self.isStandingStill else { break }
                recorded = true
                self.recordTrackPoint(location)
            case .paused, .tentativeResume:
                // updateAutoPause holds resume fixes itself.
                break
            }

            let mode = self.battery.recommendedMode(
                distanceToNextTurn: self.navigation.distanceToNextTurn,
                isOffRoute: self.navigation.isOffRoute,
                speed: self.speed,
                floor: self.ridePreferences.gpsAccuracyFloor,
                dynamicOptimization: self.ridePreferences.dynamicGPSOptimization)
            self.battery.apply(mode: mode, to: self.locationManager)
            gpsMode = mode
        }
    }

    /// Adds a fix to the saved track with the heart rate and power at the time.
    func recordTrackPoint(_ location: CLLocation) {
        recordedLocations.append(location)
        recordedHeartRates.append(heartRate > 0 ? heartRate : nil)
        recordedPowers.append(estimatedPower > 0 ? estimatedPower : nil)
        healthKit.addRoutePoint(location)
    }

    func setHeadingUpdates(enabled: Bool) {
        if enabled {
            locationManager.startUpdatingHeading()
        } else {
            locationManager.stopUpdatingHeading()
        }
    }

    private func updateNavigation(_ location: CLLocation) {
        if needsAnchor {
            needsAnchor = false
            navigation.anchorToLocation(location)
        }
        if let alert = navigation.update(location: location, riderDistance: totalDistance) {
            TurnHaptics.play(for: alert, preferences: VoiceNavigator.shared.preferences)
        }
        VoiceNavigator.shared.update(
            nav: navigation,
            speed: speed,
            heading: heading,
            isActivelyMoving: autoPauseState == .moving)
    }

    /// Adds the distance to this fix unless it starts a new leg, is indoor
    /// wander, or the rider is standing still.
    private func accumulateDistance(_ location: CLLocation) {
        if distanceTracker.consumeGapSkip(at: location) { return }
        // isStandingStill reads the poor-fix hold, so it updates first.
        distanceTracker.updatePoorFixHold(location, isSimulating: isSimulating)
        if isStandingStill || distanceTracker.isHoldingPoorFix { return }
        totalDistance += distanceTracker.commit(location)
    }

    /// Adds a held fix to the ride and the track, starting a new leg if one is pending.
    private func joinRide(_ fix: CLLocation) {
        if !distanceTracker.consumeGapSkip(at: fix) {
            totalDistance += distanceTracker.commit(fix)
        }
        recordTrackPoint(fix)
    }

    /// Detect Stops: true while this fix belongs to a stop, including a
    /// ride-off that isn't confirmed yet. A confirmed ride-off joins the ride
    /// as a straight line from where the rider stopped, and its time counts.
    private func holdForStop(_ location: CLLocation) -> Bool {
        guard isDetectingStops else {
            stopTracker.reset()
            return false
        }
        distanceTracker.updatePoorFixHold(location, isSimulating: isSimulating)
        let walking = stopDetector.isWalking

        guard stopTracker.isStopped else {
            guard looksStopped else { return false }
            _ = stopTracker.stop(at: location, walking: walking)
            let reason =
                distanceTracker.isHoldingPoorFix
                ? "poorFix"
                : walking ? "walking" : isStillByGPS ? "still" : "speed"
            DiagnosticsLog.event(
                "Stop", "stopped reason=\(reason) distance=\(String(format: "%.0f", totalDistance))m")
            return true
        }

        guard
            !distanceTracker.isHoldingPoorFix,
            !RideOffCheck.isStopped(location, floor: StopTracker.floor)
        else {
            let dropped = stopTracker.stop(at: location, walking: walking)
            if dropped >= RideOffCheck.fixes {
                DiagnosticsLog.event("Stop", "ride-off dropped held=\(dropped)")
            }
            return true
        }
        guard stopTracker.hold(location, walking: walking, recent: stopDetector.recentFixes)
        else { return true }

        let walked = stopTracker.walked
        let pushes = stopTracker.pushes(before: stopTracker.held.first ?? location)
        let held = stopTracker.finish()
        // Without GPS speed the ride-off is confirmed by distance, and this fix isn't held.
        let bySpeed = held.last === location
        let credit = held.first.map { location.timestamp.timeIntervalSince($0.timestamp) } ?? 0
        var pushed: TimeInterval = 0
        let distanceBefore = totalDistance
        for push in pushes {
            // Rests and walks between pushes aren't ridden distance.
            distanceTracker.skipNextGap()
            push.forEach(joinRide)
            if let first = push.first, let last = push.last {
                pushed += last.timestamp.timeIntervalSince(first.timestamp)
            }
        }
        let pushedDistance = totalDistance - distanceBefore
        for fix in held where fix !== location {
            joinRide(fix)
        }
        movingTime += max(0, credit) + pushed
        // The stop would read as a new one straight away.
        if let first = held.first { positionBuffer.removeFixes(before: first.timestamp) }
        DiagnosticsLog.event(
            "Stop",
            "ride-off confirmed reason=\(bySpeed ? "speed" : "distance") held=\(held.count) walked=\(walked) pushes=\(pushes.count) pushed=\(String(format: "%.0f", pushedDistance))m/\(String(format: "%.0f", pushed))s credit=\(String(format: "%.1f", credit))s"
        )
        return false
    }

    /// On departure the run-up joins the ride, the wander before it is
    /// dropped, and moving time is credited from when the rider set off.
    private func awaitDeparture(_ location: CLLocation) {
        guard
            let departure = departureDetector.add(
                location, lastWalkingStepsAt: stopDetector.lastWalkingStepsAt)
        else { return }

        // A continued ride starts a new leg here, not at the held track's end.
        for fix in departure.runUp {
            joinRide(fix)
        }
        // Record All counted the wait already.
        let credit =
            isRecordingEverything ? 0 : max(0, Date().timeIntervalSince(departure.movingSince))
        movingTime += credit

        // The wait would read as a stop to auto-pause and Detect Stops.
        positionBuffer.removeFixes(before: departure.movingSince)
        slowSampleCount = 0
        resumeGraceUntil = Date().addingTimeInterval(5)

        DiagnosticsLog.event(
            "Start",
            "departed reason=\(departure.bySpeed ? "speed" : "distance") waited=\(String(format: "%.1f", departure.waited))s held=\(departure.heldFixes) runUp=\(departure.runUp.count) rolling=\(departure.rolledFromStart) movingCredit=\(String(format: "%.1f", credit))s"
        )
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    /// Fixes older than this (s) when they arrive are cached, not live.
    static let maxFixAge: TimeInterval = 10

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        // A sim feeds its own fixes. Real ones would jump the track to wherever the watch is.
        guard !isSimulating, let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0, location.horizontalAccuracy < 50 else {
            DispatchQueue.main.async { self.rejectedFixesSinceLast += 1 }
            return
        }
        // CoreLocation can hand over a cached fix from minutes ago at start-up.
        guard -location.timestamp.timeIntervalSinceNow < Self.maxFixAge else {
            DispatchQueue.main.async { self.staleFixesSinceLast += 1 }
            return
        }
        // GPS course beats the compass for direction of travel once moving.
        if location.course >= 0 && location.speed > 0.5 {
            DispatchQueue.main.async { self.heading = location.course }
        }
        processLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            // The compass only takes over when stopped, where GPS course is unreliable.
            if self.speed <= 0.5 {
                self.heading = newHeading.trueHeading
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        DiagnosticsLog.event("AutoPause", "location error: \(error.localizedDescription)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        DiagnosticsLog.event(
            "AutoPause", "location authorization=\(manager.authorizationStatus.rawValue)")
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized")
        case .denied, .restricted:
            print("Location denied")
        default:
            break
        }
    }
}
