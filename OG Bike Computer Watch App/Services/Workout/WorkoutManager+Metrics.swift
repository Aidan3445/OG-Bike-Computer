//
//  WorkoutManager+Metrics.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Speed, elevation, grade, power and heart rate as the ride goes.
extension WorkoutManager {
    func updateExtendedMetrics(_ location: CLLocation) {
        let fixSpeed = max(location.speed, 0)
        if fixSpeed > maxSpeed { maxSpeed = fixSpeed }
        splitTracker.record(speed: fixSpeed)

        updateGPSElevation(location)

        let grade = gradeEstimator.update(
            location: location,
            routeGrade: GradeEstimator.routeGrade(from: navigation),
            current: currentGrade,
            smoothing: ridePreferences.elevationSmoothing)
        if grade != currentGrade { currentGrade = grade }

        updatePower(speed: fixSpeed)
    }

    /// A heart rate sample, from HealthKit or a sim.
    func recordHeartRate(_ value: Double) {
        heartRateStat.add(value)
        averageHeartRate = heartRateStat.average
        if value > maxHeartRate { maxHeartRate = value }
        splitTracker.record(heartRate: value)
    }

    private func updatePower(speed: Double) {
        guard speed > PowerEstimator.minSpeed else {
            estimatedPower = 0
            return
        }
        let power = PowerEstimator.watts(speed: speed, gradePercent: currentGrade, mass: totalMass)
        estimatedPower = power
        if power > maxPower { maxPower = power }
        powerStat.add(power)
        averagePower = powerStat.average
    }
}
