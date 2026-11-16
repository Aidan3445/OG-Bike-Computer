//
//  StopDetector.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import CoreMotion

/// Tells riding from standing around: when GPS last saw riding speed, and
/// whether the step counter says the rider is walking.
final class StopDetector {
    /// Position buffer speed (m/s) under which the rider is standing still.
    static let standingStillSpeed = 0.7
    /// GPS speed (m/s) that counts as riding. Walking to a door, stairs and
    /// elevators all stay under it.
    static let ridingSpeed = 2.0
    /// How recent (s) riding speed has to be for the barometer to book climbing.
    static let ridingWindow: TimeInterval = 3
    /// Steps per second that count as walking. A slow walk is about 1.5.
    static let walkingCadence = 1.0
    /// How recent (s) walking steps have to be. The pedometer reports in batches.
    static let walkingStepsWindow: TimeInterval = 15
    /// How long (s) under riding speed before steps count as walking, so a
    /// false step or two while riding never stops the ride.
    static let walkingRidingWindow: TimeInterval = 10

    private(set) var lastRidingSpeedAt: Date?
    private(set) var lastWalkingStepsAt: Date?
    private(set) var stepCount = 0
    private(set) var stepCadence: Double?
    private(set) var isPedometerRunning = false

    private let pedometer = CMPedometer()
    private var lastStepSample: (steps: Int, at: Date)?

    static var isStepCountingAvailable: Bool { CMPedometer.isStepCountingAvailable() }

    /// Recently at riding speed by GPS.
    var isAtRidingSpeed: Bool {
        guard let lastRidingSpeedAt else { return false }
        return Date().timeIntervalSince(lastRidingSpeedAt) <= Self.ridingWindow
    }

    /// Steps with no riding speed for a while. Slow riding has no steps, so a
    /// climb at walking pace keeps counting.
    var isWalking: Bool {
        let now = Date()
        guard let lastWalkingStepsAt,
            now.timeIntervalSince(lastWalkingStepsAt) <= Self.walkingStepsWindow
        else { return false }
        guard let lastRidingSpeedAt else { return true }
        return now.timeIntervalSince(lastRidingSpeedAt) > Self.walkingRidingWindow
    }

    func noteFix(_ location: CLLocation) {
        if location.speedAccuracy >= 0, location.speed >= Self.ridingSpeed {
            lastRidingSpeedAt = location.timestamp
        }
    }

    func resetRidingSpeed() {
        lastRidingSpeedAt = nil
    }

    func startPedometer() {
        guard !isPedometerRunning, Self.isStepCountingAvailable else { return }
        isPedometerRunning = true
        stepCount = 0
        stepCadence = nil
        lastStepSample = nil
        lastWalkingStepsAt = nil
        pedometer.startUpdates(from: Date()) { [weak self] data, _ in
            guard let data else { return }
            DispatchQueue.main.async { self?.handlePedometer(data) }
        }
    }

    func stopPedometer() {
        guard isPedometerRunning else { return }
        pedometer.stopUpdates()
        isPedometerRunning = false
        lastWalkingStepsAt = nil
    }

    private func handlePedometer(_ data: CMPedometerData) {
        let steps = data.numberOfSteps.intValue
        let cadence = data.currentCadence?.doubleValue
        defer {
            stepCount = steps
            stepCadence = cadence
            lastStepSample = (steps, data.endDate)
        }
        guard let last = lastStepSample, steps > last.steps else { return }
        let span = data.endDate.timeIntervalSince(last.at)
        let rate = cadence ?? (span > 0 ? Double(steps - last.steps) / span : 0)
        if rate >= Self.walkingCadence {
            lastWalkingStepsAt = data.endDate
        }
    }
}
