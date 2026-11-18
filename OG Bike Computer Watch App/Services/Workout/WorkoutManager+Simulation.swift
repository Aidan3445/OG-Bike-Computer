//
//  WorkoutManager+Simulation.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Sim rides replay a GPX track through `processLocation`. They have a
/// session for mirroring but no workout builder, skip auto-pause, and never save.
extension WorkoutManager {
    #if DEBUG
        func startSimulation(activity: ActivityType) {
            currentActivity = activity
            isSimulating = true

            do {
                try healthKit.makeSession(activity: activity, withBuilder: false, delegate: self)
            } catch {
                print("[Sim] Failed to create workout session: \(error)")
            }
            startMirroring(label: "sim start")
            healthKit.startActivity()
            startVoice()

            workoutStartDate = Date()
            timerStart = workoutStartDate
            timerAccumulated = 0
            initialRideStartDate = workoutStartDate
            startDisplayTimer()

            isActive = true
            isPaused = false
            resetMotion(anchor: nil, skipGap: false, awaitDeparture: false)
            splitTracker.startNew(at: rideTotals)
            initialRouteName = navigation.processedRoute?.name
            elevationTracker.startBarometer(gain: 0, loss: 0)
            // Sim rides have no ride ID, so their trace gets its own.
            openTraceFiles(rideID: UUID())
            startAltimeter()
            startTelemetryTimer()
        }
    #endif

    /// Heart rate comes from the track when it has it, otherwise it and
    /// calories are made up from the power estimate. Rough on purpose.
    func simulateBodyMetrics(_ location: CLLocation, previousFix: CLLocation?) {
        if let trackHR = simTrackHeartRate {
            heartRate = trackHR
        } else {
            let target = min(185, 75 + estimatedPower * 0.4)
            heartRate = heartRate == 0 ? target : heartRate + (target - heartRate) * 0.1
        }
        recordHeartRate(heartRate)

        // About 1 kcal burned per kJ of work at the pedals.
        if let previousFix {
            let dt = min(5, max(0, location.timestamp.timeIntervalSince(previousFix.timestamp)))
            activeCalories += estimatedPower * dt / 1000
        }
    }
}
