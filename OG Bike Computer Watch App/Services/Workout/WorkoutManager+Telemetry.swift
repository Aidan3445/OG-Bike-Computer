//
//  WorkoutManager+Telemetry.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import Foundation
import HealthKit

/// Live ride numbers for the phone's Live Activity, sent over the mirrored
/// workout session.
extension WorkoutManager {
    /// Mirroring launches the phone app and keeps it running for the ride,
    /// for telemetry and spoken alerts.
    func startMirroring(label: String) {
        isMirroringReady = false
        let requested = Date()
        DiagnosticsLog.event("Mirroring", "\(label) requested")
        session?.startMirroringToCompanionDevice { [weak self] success, error in
            let wait = String(format: "%.1f", Date().timeIntervalSince(requested))
            DiagnosticsLog.event(
                "Mirroring",
                "\(label) result success=\(success) after=\(wait)s error=\(error?.localizedDescription ?? "none")"
            )
            guard success else { return }
            DispatchQueue.main.async { self?.isMirroringReady = true }
        }
    }

    func startTelemetryTimer() {
        earlyTelemetrySessionID = UUID().uuidString
        earlyTelemetryUntil = Date().addingTimeInterval(90)
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(
            withTimeInterval: ridePreferences.telemetryRate.interval, repeats: true
        ) { [weak self] _ in
            self?.sendTelemetry()
        }
    }

    func stopTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
        if let sessionID = earlyTelemetrySessionID {
            ConnectivityManager.shared.sendEarlyRideEnded(sessionID: sessionID)
            earlyTelemetrySessionID = nil
        }
    }

    /// The phone has the mirrored session, so the direct copy can stop.
    func stopEarlyTelemetry() {
        guard earlyTelemetrySessionID != nil else { return }
        DiagnosticsLog.event("Mirroring", "early telemetry stopped, phone has session")
        earlyTelemetrySessionID = nil
    }

    /// A failed send marks mirroring down, then optimistically back up after
    /// 3 s. The next send shows whether it really is.
    func markMirroringFailed() {
        DispatchQueue.main.async { [self] in
            guard self.isActive else { return }
            DiagnosticsLog.event(
                "AutoPause", "telemetry send failed, mirroring marked down, retry in 3s")
            self.isMirroringReady = false
            self.mirroringRetryWorkItem?.cancel()
            let item = DispatchWorkItem { [weak self] in
                guard let self, self.isActive, self.session != nil else { return }
                DiagnosticsLog.event("AutoPause", "mirroring retry, marked ready")
                self.isMirroringReady = true
                self.mirroringRetryWorkItem = nil
            }
            self.mirroringRetryWorkItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
        }
    }

    private func sendTelemetry() {
        if earlyTelemetrySessionID != nil, Date() > earlyTelemetryUntil {
            earlyTelemetrySessionID = nil
        }
        let workoutSession = isMirroringReady ? session : nil
        if workoutSession == nil { skippedTelemetrySends += 1 }
        guard workoutSession != nil || earlyTelemetrySessionID != nil else { return }

        let payload = telemetryPayload()

        if let sessionID = earlyTelemetrySessionID {
            var early = payload
            early["sessionID"] = sessionID
            ConnectivityManager.shared.sendEarlyTelemetry(early)
        }

        guard let workoutSession, let data = try? JSONEncoder().encode(payload) else { return }

        lastTelemetrySendAt = Date()
        workoutSession.sendToRemoteWorkoutSession(data: data) { [weak self] success, error in
            let result =
                error.map { "error: \($0.localizedDescription)" } ?? (success ? "ok" : "failed")
            DispatchQueue.main.async { self?.lastTelemetryResult = result }
            if let error {
                print("[Telemetry] send error: \(error)")
                self?.markMirroringFailed()
            }
        }
    }

    /// Optional values are left out when they have nothing to show.
    private func telemetryPayload() -> [String: String] {
        var payload: [String: String] = [
            "type": "telemetry",
            "ts": String(Date().timeIntervalSince1970),
            "elapsedTime": String(elapsedTime),
            "movingTime": String(movingTime),
            "distance": String(totalDistance),
            "avgSpeed": String(averageSpeed),
            "speed": String(speed),
            "isPaused": String(isPaused),
            "isAutoPaused": String(isAutoPaused),
        ]

        if heartRate > 0 { payload["heartRate"] = String(heartRate) }
        if maxSpeed > 0 { payload["maxSpeed"] = String(maxSpeed) }
        if averageHeartRate > 0 { payload["avgHR"] = String(averageHeartRate) }
        if maxHeartRate > 0 { payload["maxHR"] = String(maxHeartRate) }
        if activeCalories > 0 { payload["calories"] = String(activeCalories) }
        if currentElevation != 0 { payload["elevation"] = String(currentElevation) }
        if liveElevationGain > 0 { payload["elevGain"] = String(liveElevationGain) }
        if liveElevationLoss > 0 { payload["elevLoss"] = String(liveElevationLoss) }
        if highestElevation > -Double.greatestFiniteMagnitude {
            payload["highElev"] = String(highestElevation)
        }
        if currentGrade != 0 { payload["grade"] = String(currentGrade) }
        if estimatedPower > 0 { payload["power"] = String(estimatedPower) }

        if let loc = currentLocation {
            payload["lat"] = String(loc.coordinate.latitude)
            payload["lon"] = String(loc.coordinate.longitude)
        }

        guard hasRoute else { return payload }

        payload["routeRemaining"] = String(navigation.distanceRemaining)
        payload["isOffRoute"] = String(navigation.isOffRoute)
        if let routeID = activeRoute?.id {
            payload["activeRouteID"] = routeID.uuidString
        }

        // Off route, the missed turn takes the upcoming turn's place on the Live Activity.
        if navigation.isOffRoute {
            payload["distOffRoute"] = String(navigation.nearestRouteDistance)
            if let missed = navigation.missedTurn {
                // Worded here so the phone widget doesn't need TurnDirection's labels.
                let suffix = missed.direction == .uTurn ? "" : " Turn"
                payload["missedTurnLabel"] = "Missed \(missed.direction.label)\(suffix)"
                if let desc = missed.description,
                    let onto = desc.range(of: " onto ", options: .caseInsensitive)
                {
                    let name = String(desc[onto.upperBound...]).trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty {
                        payload["missedTurnCue"] = "onto \(name)"
                    }
                }
            }
        } else {
            payload["distToTurn"] = String(navigation.distanceToNextTurn)
            if let turn = navigation.nextTurn {
                payload["turnDir"] = turn.direction.label
                payload["turnIcon"] = turn.direction.icon
                if let desc = turn.description {
                    payload["turnCue"] = desc
                }
            }
        }
        return payload
    }
}
