//
//  WorkoutManager+SessionDelegate.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import HealthKit

/// Session state changes, including pause, resume and end from the phone
/// through the mirrored session, and messages the phone sends back.
extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didChangeTo toState: HKWorkoutSessionState,
        from fromState: HKWorkoutSessionState,
        date: Date
    ) {
        DiagnosticsLog.event(
            "Mirroring", "session state \(fromState.rawValue) -> \(toState.rawValue)")

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }

            // A change this device asked for. Internal state is already in sync.
            if self.expectedSessionStates.contains(toState),
                Date().timeIntervalSince(self.expectedSessionStatesAt) < 30
            {
                self.expectedSessionStates.remove(toState)
                return
            }
            self.expectedSessionStates = []
            DiagnosticsLog.event(
                "AutoPause",
                "unexpected session state \(fromState.rawValue) -> \(toState.rawValue) active=\(self.isActive)"
            )

            // Anything else came from the phone.
            guard self.isActive else { return }

            switch toState {
            case .paused where fromState == .running:
                print("[Remote] Pause received from phone")
                // The session is already paused, so only the watch's side follows.
                self.markPaused()
                self.stopMotionForPause()

            case .running where fromState == .paused:
                print("[Remote] Resume received from phone")
                self.markRunning()
                self.restartMotion()
                self.locationManager.startUpdatingLocation()
                self.locationManager.startUpdatingHeading()

            case .ended, .stopped:
                print("[Remote] End received from phone")
                self.stop(save: true)

            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession, didFailWithError error: Error) {
        print("Workout session error: \(error)")
    }

    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didDisconnectFromRemoteDeviceWithError error: Error?
    ) {
        print("[Mirroring] Disconnected from phone: \(error?.localizedDescription ?? "clean")")
        markMirroringFailed()
    }

    /// From the phone: "alertAck" when it starts speaking an alert,
    /// "alertFinish" when it's done (the watch's alert queue moves on from
    /// that, not a duration guess), "alertNack" when it dropped one unspoken,
    /// and "resumeRide" for a resume it couldn't send as a state change.
    func workoutSession(
        _ workoutSession: HKWorkoutSession,
        didReceiveDataFromRemoteWorkoutSession data: [Data]
    ) {
        let now = Date().timeIntervalSince1970

        for item in data {
            guard let payload = try? JSONDecoder().decode([String: String].self, from: item),
                let type = payload["type"]
            else { continue }

            // Old messages flushed after a relaunch are stale.
            if let tsString = payload["ts"], let ts = Double(tsString), now - ts > 10 {
                continue
            }

            switch type {
            case "alertAck":
                guard let id = payload["id"].flatMap(UUID.init(uuidString:)) else { continue }
                DispatchQueue.main.async { ConnectivityManager.shared.onAlertAckReceived?(id) }
            case "alertFinish":
                guard let id = payload["id"].flatMap(UUID.init(uuidString:)) else { continue }
                DispatchQueue.main.async { ConnectivityManager.shared.onAlertFinishReceived?(id) }
            case "alertNack":
                guard let id = payload["id"].flatMap(UUID.init(uuidString:)) else { continue }
                DispatchQueue.main.async { ConnectivityManager.shared.onAlertNackReceived?(id) }
            case "resumeRide":
                DispatchQueue.main.async { [weak self] in
                    guard let self, self.isActive, self.isPaused else { return }
                    print("[Remote] Resume received from phone during auto-pause")
                    self.resume()
                }
            default:
                break
            }
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(
        _ workoutBuilder: HKLiveWorkoutBuilder,
        didCollectDataOf collectedTypes: Set<HKSampleType>
    ) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            DispatchQueue.main.async {
                switch quantityType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    let hr = statistics?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
                    self.heartRate = hr
                    if hr > 0 {
                        self.recordHeartRate(hr)
                    }
                case HKQuantityType(.activeEnergyBurned):
                    let calories = statistics?.sumQuantity()?.doubleValue(for: .kilocalorie()) ?? 0
                    self.activeCalories = self.caloriesBase + calories
                default:
                    break
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
