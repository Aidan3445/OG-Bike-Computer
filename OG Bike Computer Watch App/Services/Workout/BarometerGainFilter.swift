//
//  BarometerGainFilter.swift
//  OG Bike Computer Watch App
//

import Foundation

/// Turns relative altitude readings into booked gain and loss, ignoring
/// sensor noise and impossible jumps.
///
/// `noiseFloor` is the smallest change that books. `maxVerticalSpeed` and
/// `minJumpAllowance` set how far the reading can move between samples
/// before it counts as a jump.
struct BarometerGainFilter {
    enum Outcome: Equatable {
        case gain(Double)
        case loss(Double)
        case skipped(String)
    }

    var noiseFloor = 1.0
    static let maxVerticalSpeed = 5.0
    static let minJumpAllowance = 5.0
    /// Readings come every few seconds, so a longer gap means updates stalled
    /// and can't excuse a bigger jump.
    static let maxJumpGap: TimeInterval = 5

    private(set) var reference: Double?
    private var last: (reading: Double, time: TimeInterval)?

    /// Start over, for a new altimeter session.
    mutating func reset() {
        reference = nil
        last = nil
    }

    /// Books nothing and follows the reading.
    mutating func hold(_ reading: Double, at time: TimeInterval) {
        reference = reading
        last = (reading, time)
    }

    /// Moves the reference to the latest reading.
    mutating func rebase() {
        reference = last?.reading
    }

    /// Books nothing but keeps the reference, so a real change made while
    /// stopped (stairs, a curb) books once moving again. Jumps still fold out.
    @discardableResult
    mutating func freeze(_ reading: Double, at time: TimeInterval) -> String? {
        defer { last = (reading, time) }
        return foldJump(reading, at: time)
    }

    /// A reading while the ride is booking climbing.
    mutating func ingest(_ reading: Double, at time: TimeInterval) -> Outcome {
        defer { last = (reading, time) }

        if let jumpReason = foldJump(reading, at: time) {
            return .skipped(jumpReason)
        }

        guard let ref = reference else {
            reference = reading
            return .skipped("noReference")
        }

        let delta = reading - ref
        if delta > noiseFloor {
            reference = reading
            return .gain(delta)
        }
        if delta < -noiseFloor {
            reference = reading
            return .loss(-delta)
        }
        return .skipped("noiseFloor")
    }

    /// Moves the reference by a baseline reset or impossible jump so it never
    /// books, and returns why. Nil for an ordinary reading.
    private mutating func foldJump(_ reading: Double, at time: TimeInterval) -> String? {
        guard let last else { return nil }
        let jump = reading - last.reading
        let elapsed = min(max(time - last.time, 0), Self.maxJumpGap)
        let allowance = Self.minJumpAllowance + Self.maxVerticalSpeed * elapsed
        let isBaselineReset = reading == 0 && abs(jump) > 1
        guard isBaselineReset || abs(jump) > allowance else { return nil }
        reference? += jump
        return isBaselineReset ? "baselineReset" : "jump"
    }
}
