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
/// leaves stops out (`isStandingStill`). Record All counts everything.
extension WorkoutManager {
    /// Slow GPS speed readings in a row that pause.
    static let slowSamplesForPause = 5
    /// Fast readings in a row that confirm a resume, along with the time and distance below.
    static let fastSamplesForResume = 5
    static let minTentativeDuration: TimeInterval = 3
    static let resumeDistance: Double = 15
    /// How long a silent probe samples GPS before re-pausing.
    static let probeWindow: TimeInterval = 15
    /// Seconds with no GPS fix that count as stopped.
    static let gpsSilenceForPause: TimeInterval = 8

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

    /// Stopped, or walking around a stop, in Detect Stops. Auto-pause
    /// handles stops itself, and Record All counts them.
    var isStandingStill: Bool {
        guard !isSimulating, ridePreferences.autoPause.mode == .detectStops else { return false }
        return distanceTracker.isHoldingPoorFix || stopDetector.isWalking
            || (positionBuffer.isReady && positionBuffer.speed < StopDetector.standingStillSpeed)
    }

    func updateAutoPause() {
        // CL speed can freeze at a stale value when stopped, so pausing and
        // resuming trust the position buffer. Traced in every mode.
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

        let pauseThreshold = ridePreferences.autoPause.speedThreshold * 2.23694
        let resumeThreshold = pauseThreshold + 1.0

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
            // A stuck CL speed moves nothing, so it can't start a resume.
            guard bufferSpeedMPH >= resumeThreshold else { return }
            DiagnosticsLog.event(
                "AutoPause",
                "tentative started bufferSpeed=\(String(format: "%.1f", bufferSpeedMPH))mph")
            cancelPauseProbe()
            autoPauseState = .tentativeResume
            tentative.begin(with: currentLocation, fastSamples: 1)

        case .tentativeResume:
            if bufferSpeedMPH >= resumeThreshold {
                tentative.countFastSample()
                let elapsed = tentative.elapsed
                guard tentative.fastSampleCount >= Self.fastSamplesForResume,
                    elapsed >= Self.minTentativeDuration,
                    tentative.distance >= Self.resumeDistance
                else { return }

                DiagnosticsLog.event(
                    "AutoPause",
                    "resume confirmed samples=\(tentative.fastSampleCount) elapsed=\(String(format: "%.1f", elapsed))s distance=\(String(format: "%.1f", tentative.distance))m silentProbe=\(isSilentProbe)"
                )
                cancelPauseProbe()
                commitTentativeBuffer()
                resumeSession()
                autoPauseState = .moving
                if navigationAlerts.autoPauseAlerts.enabled {
                    VoiceNavigator.shared.announceAutoResume(
                        mode: navigationAlerts.autoPauseAlerts.resumeMode)
                }
            } else if !isSilentProbe {
                // A silent probe gets its whole window, timed in tickAutoPauseFallback.
                DiagnosticsLog.event(
                    "AutoPause",
                    "tentative regressed bufferSpeed=\(String(format: "%.1f", bufferSpeedMPH))mph samples=\(tentative.fastSampleCount)"
                )
                tentative.clear()
                autoPauseState = .paused
                schedulePauseProbe()
            }
        }
    }

    /// Once a second. GPS slows to a trickle when the rider stops, so pausing
    /// can't wait for the next fix.
    func tickAutoPauseFallback() {
        // Sims skip auto-pause, and a pause here would start real GPS.
        guard isActive, !isSimulating, ridePreferences.autoPause.enabled else { return }

        if isSilentProbe,
            autoPauseState == .tentativeResume,
            let probeStart = probeStartedAt,
            Date().timeIntervalSince(probeStart) >= Self.probeWindow
        {
            endSilentProbe()
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
    /// time counts as moving. Only the distance between staged fixes counts,
    /// not the gap back to where the rider stopped.
    func commitTentativeBuffer() {
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
