//
//  WorkoutManager+Splits.swift
//  OG Bike Computer Watch App
//

import Foundation

/// Split announcements every split length of riding.
extension WorkoutManager {
    var rideTotals: RideTotals {
        RideTotals(
            distance: totalDistance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            elevationGain: liveElevationGain,
            elevationLoss: liveElevationLoss,
            calories: activeCalories)
    }

    func checkSplit() {
        let prefs = navigationAlerts.splitAlerts
        guard prefs.enabled,
            let splitStats = splitTracker.completeIfDue(
                splitLength: prefs.splitDistance, at: rideTotals)
        else { return }

        VoiceNavigator.shared.announceSplit(
            number: splitTracker.number,
            splitDistance: prefs.splitDistance,
            splitStats: splitStats,
            rideStats: currentRideStats(),
            metrics: prefs.metrics,
            mode: prefs.mode
        )
    }

    func currentRideStats() -> SplitStats {
        SplitStats(
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            distance: totalDistance,
            averageSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            averageHeartRate: heartRateStat.count > 0 ? averageHeartRate : 0,
            maxHeartRate: maxHeartRate,
            elevationGain: liveElevationGain,
            elevationLoss: liveElevationLoss,
            calories: activeCalories
        )
    }

    func currentSplitProgress() -> SplitProgress {
        splitTracker.progress(splitLength: navigationAlerts.splitAlerts.splitDistance)
    }
}
