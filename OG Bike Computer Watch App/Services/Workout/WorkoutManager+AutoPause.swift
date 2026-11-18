//
//  WorkoutManager+AutoPause.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import HealthKit

enum AutoPauseState {
    case moving
    case paused
    /// Moving again but not confirmed. Fixes wait in `tentative` until it is.
    case tentativeResume
}

/// The stop modes. Auto-Pause pauses the session when the rider stops and
/// resumes once they've clearly set off. Detect Stops keeps recording but
/// leaves stops out (`isStandingStill`). Record All counts everything. Both
/// stop modes confirm a ride-off with `RideOffCheck`; Auto-Pause holds it to
/// the rider's pause speed.
extension WorkoutManager {
    /// Slow GPS speed readings in a row that pause.
    static let slowSamplesForPause = 5
    /// How long a silent probe, or any resume check, samples GPS before re-pausing.
    static let probeWindow: TimeInterval = 15
    /// Seconds with no GPS fix that count as stopped.
    static let gpsSilenceForPause: TimeInterval = 8
    /// The gap from the stop to the resume backfills as a straight line up to
    /// this speed (m/s) and distance (m). Past either it's a jump, not riding.
    static let maxBackfillSpeed = 15.0
    static let maxBackfillGap: Double = 1000
    /// Meters of GPS error the backfill allows on top of the speed limit.
    static let backfillSlack: Double = 15

    /// Position buffer speed (m/s) under which auto-pause pauses: the rider's
    /// pause speed, capped at 6 m per 8 s window.
    var positionPauseSpeed: Double {
        min(ridePreferences.autoPause.speedThreshold, 0.75)
    }

    /// Every second and every real height change counts. Only clear errors
    /// (stale or vague fixes, barometer jumps and noise) are still filtered.
    var isRecordingEverything: Bool {
        ridePreferences.autoPause.mode == .recordAll
    }

    /// Auto-pause handles stops itself, and Record All counts them.
    var isDetectingStops: Bool {
        !isSimulating && ridePreferences.autoPause.mode == .detectStops
    }

    /// Stopped, or walking around a stop, in Detect Stops. A stop lasts until
    /// the ride-off is confirmed.
    var isStandingStill: Bool {
        isDetectingStops && (stopTracker.isStopped || looksStopped)
    }

    /// This moment reads as a stop: a vague indoor fix that hasn't gone
    /// anywhere, walking, or still by GPS speed or position. Walking is held
    /// until the rider rides again, then any pushing counts (`StopTracker.pushes`).
    var looksStopped: Bool {
        if distanceTracker.isHoldingPoorFix || stopDetector.isWalking { return true }
        let recent = stopDetector.recentFixes
        let floor = StopTracker.floor
        // Position alone can't see slow progress, so GPS speed can vouch for it.
        if RideOffCheck.isMovingSteadily(recent, floor: floor) { return false }
        return RideOffCheck.isStoppedSteadily(recent, floor: floor) || isStillByGPS
    }

    var isStillByGPS: Bool {
        positionBuffer.isReady && positionBuffer.speed < StopDetector.standingStillSpeed
    }

    func updateAutoPause() {
        // CL speed can freeze at a stale value when stopped, so pausing also
        // checks the position buffer, and a resume has to cover ground.
        // Traced in every mode.
        let bufferSpeed = positionBuffer.speed
        let bufferSpeedMPH = bufferSpeed * 2.23694
        let bufferDisplacement = positionBuffer.displacement
        let clSpeedMPH = speed * 2.23694
        traceBufferSpeedMPH = bufferSpeedMPH
        traceBufferDisplacement = bufferDisplacement
        traceCLSpeedMPH = clSpeedMPH

        guard ridePreferences.autoPause.enabled else {
            if isAutoPaused {
                DiagnosticsLog.event(
                    "AutoPause", "auto-pause turned off while \(autoPauseState), resumed")
                if autoPauseState == .tentativeResume {
                    commitTentativeBuffer()
                }
                cancelPauseProbe()
                resumeSession()
                autoPauseState = .moving
            }
            return
        }

        let pauseSpeed = ridePreferences.autoPause.speedThreshold
        let pauseThreshold = pauseSpeed * 2.23694

        switch autoPauseState {
        case .moving:
            // Waiting to set off isn't a stop to announce.
            guard Date() >= resumeGraceUntil, !departureDetector.isWaiting else { return }

            slowSampleCount = clSpeedMPH < pauseThreshold ? slowSampleCount + 1 : 0
            let velocitySaysPaused = slowSampleCount >= Self.slowSamplesForPause
            // Catches CL speed frozen above the threshold while the rider is stopped.
            let positionSaysPaused = positionBuffer.isReady && bufferSpeed < positionPauseSpeed
            guard velocitySaysPaused || positionSaysPaused, !isPaused else { return }

            DiagnosticsLog.event(
                "AutoPause",
                "paused reason=\(velocitySaysPaused ? "velocity" : "position") slowSamples=\(slowSampleCount) clSpeed=\(String(format: "%.1f", clSpeedMPH))mph bufferSpeed=\(String(format: "%.1f", bufferSpeedMPH))mph cutoff=\(Self.mph(positionPauseSpeed))mph displacement=\(String(format: "%.1f", bufferDisplacement))m"
            )
            enterAutoPause()

        case .paused:
            // Anything over the pause speed can start a resume. RideOffCheck
            // tells it from wander and a stuck reading.
            guard let location = currentLocation, RideOffCheck.isMoving(location, floor: pauseSpeed)
            else { return }
            DiagnosticsLog.event(
                "AutoPause",
                "tentative started speed=\(Self.mph(location.speed))mph speedAcc=\(String(format: "%.2f", location.speedAccuracy))"
            )
            cancelPauseProbe()
            autoPauseState = .tentativeResume
            tentative.begin(with: location, fastSamples: 1)

        case .tentativeResume:
            guard let location = currentLocation else { return }
            let moving = RideOffCheck.isMoving(location, floor: pauseSpeed)
            if RideOffCheck.isStopped(location, floor: pauseSpeed) {
                if isSilentProbe {
                    // A silent probe gets its whole window, timed in
                    // tickAutoPauseFallback. The run starts over.
                    if !tentative.locations.isEmpty { tentative.begin(with: nil, fastSamples: 0) }
                } else {
                    regressTentative("speed=\(Self.mph(location.speed))mph")
                }
                return
            }
            // A run starts on a moving fix, so a probe's wander stays out.
            guard moving || !tentative.locations.isEmpty else { return }

            // This fix rides on as a moving one if it confirms the resume.
            let run =
                tentative.locations.filter {
                    location.timestamp.timeIntervalSince($0.timestamp) <= RideOffCheck.window
                } + [location]
            guard RideOffCheck.confirms(run, floor: pauseSpeed) else {
                tentative.append(location)
                if moving { tentative.countFastSample() }
                return
            }
            DiagnosticsLog.event(
                "AutoPause",
                "resume confirmed fixes=\(run.count) elapsed=\(String(format: "%.1f", tentative.elapsed))s distance=\(String(format: "%.1f", tentative.distance))m silentProbe=\(isSilentProbe)"
            )
            cancelPauseProbe()
            commitTentativeBuffer()
            resumeSession()
            autoPauseState = .moving
            // The stop would read as a new pause straight away.
            if let start = run.first { positionBuffer.removeFixes(before: start.timestamp) }
            slowSampleCount = 0
            if navigationAlerts.autoPauseAlerts.enabled {
                VoiceNavigator.shared.announceAutoResume(
                    mode: navigationAlerts.autoPauseAlerts.resumeMode)
            }
        }
    }

    private func regressTentative(_ reason: String) {
        DiagnosticsLog.event(
            "AutoPause",
            "tentative regressed \(reason) fixes=\(tentative.locations.count) samples=\(tentative.fastSampleCount)"
        )
        tentative.clear()
        autoPauseState = .paused
        schedulePauseProbe()
    }

    /// Once a second. GPS slows to a trickle when the rider stops, so pausing
    /// can't wait for the next fix.
    func tickAutoPauseFallback() {
        // Sims skip auto-pause, and a pause here would start real GPS.
        guard isActive, !isSimulating, ridePreferences.autoPause.enabled else { return }

        // A resume check that hasn't confirmed in its window goes back to
        // paused, so it can't wait forever on fixes that never come.
        if autoPauseState == .tentativeResume,
            let start = isSilentProbe ? probeStartedAt : tentative.startTime,
            Date().timeIntervalSince(start) >= Self.probeWindow
        {
            if isSilentProbe {
                endSilentProbe()
            } else {
                regressTentative("timedOut=\(Int(Self.probeWindow))s")
            }
            return
        }

        guard !isPaused, autoPauseState == .moving, !departureDetector.isWaiting else { return }

        positionBuffer.evictStale()

        guard let last = lastLocationUpdateAt else { return }
        let silence = Date().timeIntervalSince(last)
        guard silence >= Self.gpsSilenceForPause, Date() >= resumeGraceUntil else { return }

        DiagnosticsLog.event(
            "AutoPause", "paused reason=gpsSilence silence=\(String(format: "%.1f", silence))s")
        speed = 0
        positionBuffer.removeAll()
        enterAutoPause()
    }

    /// The resume is confirmed: staged fixes join the ride and the staged
    /// time counts as moving. The stretch from where the rider stopped to the
    /// first staged fix counts too, as a straight line, unless no bike could
    /// have covered it in the time.
    func commitTentativeBuffer() {
        if let first = tentative.locations.first, let stoppedAt = distanceTracker.lastCommitted,
            !distanceTracker.skipsNextGap
        {
            let gap = first.distance(from: stoppedAt)
            let seconds = max(first.timestamp.timeIntervalSince(stoppedAt.timestamp), 0)
            let reach = min(Self.maxBackfillSpeed * seconds + Self.backfillSlack, Self.maxBackfillGap)
            if gap <= reach {
                totalDistance += gap
            } else {
                DiagnosticsLog.event(
                    "AutoPause",
                    "resume gap skipped gap=\(String(format: "%.0f", gap))m after=\(String(format: "%.0f", seconds))s")
            }
        }
        totalDistance += tentative.distance
        for location in tentative.locations {
            recordTrackPoint(location)
        }
        if let start = tentative.startTime {
            movingTime += Date().timeIntervalSince(start)
        }
        if let last = tentative.locations.last {
            distanceTracker.anchor(at: last)
        }
        tentative.clear()
    }

    /// Ends auto-pause for a stop or hold. A silent probe's fixes are
    /// unverified, since the rider was paused, so they're dropped.
    func settleTentativeResume() {
        if autoPauseState == .tentativeResume {
            if isSilentProbe {
                tentative.clear()
            } else {
                commitTentativeBuffer()
            }
        }
        cancelPauseProbe()
    }

    func cancelPauseProbe() {
        pauseProbeTimer?.invalidate()
        pauseProbeTimer = nil
        isSilentProbe = false
        probeStartedAt = nil
        probeDueAt = nil
    }

    private func enterAutoPause() {
        autoPauseState = .paused
        pauseSession()
        slowSampleCount = 0
        if navigationAlerts.autoPauseAlerts.enabled {
            VoiceNavigator.shared.announceAutoPause(
                mode: navigationAlerts.autoPauseAlerts.pauseMode)
        }
        schedulePauseProbe()
    }

    // MARK: - Silent probe

    // While the session is paused, watchOS stops feeding HealthKit and soon
    // after CoreLocation, so a silent probe wakes both every so often to see
    // whether the rider has set off again.

    private func schedulePauseProbe() {
        let range = AutoPausePreferences.resumeProbeIntervalRange
        let interval = min(max(ridePreferences.autoPause.resumeProbeInterval, range.lowerBound), range.upperBound)
        pauseProbeTimer?.invalidate()
        let due = Date().addingTimeInterval(interval)
        probeDueAt = due
        DiagnosticsLog.event(
            "AutoPause",
            "probe scheduled interval=\(Int(interval))s due=\(String(format: "%.3f", due.timeIntervalSince1970))"
        )
        pauseProbeTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: false) {
            [weak self] _ in
            self?.beginSilentProbe()
        }
    }

    /// Wakes the session and GPS without looking resumed: `isPaused` stays
    /// true and nothing is announced unless real movement confirms a resume.
    private func beginSilentProbe() {
        guard isActive, autoPauseState == .paused, ridePreferences.autoPause.enabled else {
            DiagnosticsLog.event("AutoPause", "probe fired but skipped, state=\(autoPauseState)")
            cancelPauseProbe()
            return
        }

        let late = probeDueAt.map { Date().timeIntervalSince($0) } ?? 0
        DiagnosticsLog.event("AutoPause", "probe fired late=\(String(format: "%.1f", late))s")

        expectSessionStates([.running])
        healthKit.resume()
        locationManager.startUpdatingLocation()

        isSilentProbe = true
        probeStartedAt = Date()
        // Fixes from before the probe don't count toward a resume.
        positionBuffer.removeAll()
        lastLocationUpdateAt = nil
        tentative.begin(with: nil, fastSamples: 0)
        autoPauseState = .tentativeResume
    }

    /// The probe window ran out without a confirmed resume.
    private func endSilentProbe() {
        DiagnosticsLog.event(
            "AutoPause", "probe timed out after \(Int(Self.probeWindow))s, re-paused")
        tentative.clear()

        expectSessionStates([.paused])
        healthKit.pause()

        isSilentProbe = false
        probeStartedAt = nil
        autoPauseState = .paused
        slowSampleCount = 0
        positionBuffer.removeAll()
        schedulePauseProbe()
    }
}
