//
//  SplitTracker.swift
//  OG Bike Computer Watch App
//

import Foundation

/// The ride's running totals, as splits measure them.
struct RideTotals {
    var distance: Double = 0
    var movingTime: TimeInterval = 0
    var elapsedTime: TimeInterval = 0
    var elevationGain: Double = 0
    var elevationLoss: Double = 0
    var calories: Double = 0

    func scaled(by fraction: Double) -> RideTotals {
        RideTotals(
            distance: distance * fraction,
            movingTime: movingTime * fraction,
            elapsedTime: elapsedTime * fraction,
            elevationGain: elevationGain * fraction,
            elevationLoss: elevationLoss * fraction,
            calories: calories * fraction)
    }
}

/// Counts splits and measures each one from the totals where it started.
struct SplitTracker {
    private(set) var number = 0
    /// Ride distance at the last split boundary.
    private(set) var lastSplitDistance: Double = 0
    private var start = RideTotals()
    private var maxSpeed: Double = 0
    private var heartRate = RunningStat()

    /// Starts counting from split 0 at the current distance.
    mutating func startNew(at totals: RideTotals) {
        number = 0
        lastSplitDistance = totals.distance
        rebaseline(at: totals)
    }

    /// The next split is measured from here.
    mutating func rebaseline(at totals: RideTotals) {
        start = totals
        maxSpeed = 0
        heartRate = RunningStat()
    }

    /// After the split length changes mid-ride, lines up with the nearest
    /// boundary at or below the current distance.
    mutating func reanchor(splitLength: Double, at totals: RideTotals) {
        if splitLength > 0 {
            number = Int(totals.distance / splitLength)
            lastSplitDistance = Double(number) * splitLength
        } else {
            lastSplitDistance = totals.distance
        }
        rebaseline(at: totals)
    }

    /// Picks the split back up where it was when the ride was held. Held
    /// rides that didn't save it get a split start estimated from the
    /// ride's averages.
    mutating func restore(_ saved: SplitProgress?, splitLength: Double, at totals: RideTotals) {
        if let saved, saved.splitLength == splitLength {
            number = saved.number
            lastSplitDistance = saved.lastSplitDistance
            start = RideTotals(
                distance: saved.startDistance,
                movingTime: saved.startMovingTime,
                elapsedTime: saved.startElapsedTime,
                elevationGain: saved.startElevationGain,
                elevationLoss: saved.startElevationLoss,
                calories: saved.startCalories)
            maxSpeed = saved.maxSpeed
            heartRate = RunningStat(
                sum: saved.heartRateSum, count: saved.heartRateCount, max: saved.maxHeartRate)
        } else {
            number = Int(totals.distance / splitLength)
            lastSplitDistance = Double(number) * splitLength
            let fraction = totals.distance > 0 ? lastSplitDistance / totals.distance : 0
            rebaseline(at: totals.scaled(by: fraction))
            start.distance = lastSplitDistance
        }
    }

    func progress(splitLength: Double) -> SplitProgress {
        SplitProgress(
            splitLength: splitLength,
            number: number,
            lastSplitDistance: lastSplitDistance,
            startDistance: start.distance,
            startMovingTime: start.movingTime,
            startElapsedTime: start.elapsedTime,
            startElevationGain: start.elevationGain,
            startElevationLoss: start.elevationLoss,
            startCalories: start.calories,
            maxSpeed: maxSpeed,
            maxHeartRate: heartRate.max,
            heartRateSum: heartRate.sum,
            heartRateCount: heartRate.count
        )
    }

    mutating func record(speed: Double) {
        if speed > maxSpeed { maxSpeed = speed }
    }

    mutating func record(heartRate value: Double) {
        heartRate.add(value)
    }

    /// The split just finished, if the ride has gone a full split length
    /// past the last boundary. The next split starts measuring from here.
    mutating func completeIfDue(splitLength: Double, at totals: RideTotals) -> SplitStats? {
        guard totals.distance - lastSplitDistance >= splitLength else { return nil }
        number += 1
        lastSplitDistance += splitLength

        let movingTime = totals.movingTime - start.movingTime
        let distance = totals.distance - start.distance
        let stats = SplitStats(
            movingTime: movingTime,
            elapsedTime: totals.elapsedTime - start.elapsedTime,
            distance: distance,
            averageSpeed: movingTime > 0 ? distance / movingTime : 0,
            maxSpeed: maxSpeed,
            averageHeartRate: heartRate.average,
            maxHeartRate: heartRate.max,
            elevationGain: max(0, totals.elevationGain - start.elevationGain),
            elevationLoss: max(0, totals.elevationLoss - start.elevationLoss),
            calories: max(0, totals.calories - start.calories)
        )
        rebaseline(at: totals)
        return stats
    }
}
