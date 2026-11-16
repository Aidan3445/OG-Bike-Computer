//
//  DepartureDetector.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Holds a new ride's fixes until the rider has clearly set off, so GPS
/// wander at the start adds no track or distance. On departure it hands
/// back the run-up, which joins the ride so a ride started while rolling
/// still draws from the start.
struct DepartureDetector {
    /// Fixes in a row at riding speed that confirm departure.
    static let fastFixes = 3
    /// How far (m) the run-up has to carry the rider too. Stationary fixes
    /// at start-up can report riding speed while barely moving.
    static let distance: Double = 20
    /// Straight-line distance (m) that confirms departure on its own, for
    /// fixes with no GPS speed.
    static let fallbackDistance: Double = 100
    /// GPS speed (m/s) a fix needs to count as part of the run-up.
    static let runUpSpeed = 1.0
    static let maxFixes = 180

    struct Departure {
        let bySpeed: Bool
        /// Fixes to add to the ride before the one that confirmed departure.
        let runUp: [CLLocation]
        /// When the rider started moving, for crediting moving time.
        let movingSince: Date
        let rolledFromStart: Bool
        let heldFixes: Int
        let waited: TimeInterval
    }

    private(set) var isWaiting = false
    private var fixes: [CLLocation] = []
    private var trimmed = false
    private var start: CLLocation?
    private var waitStartedAt: Date?

    mutating func reset(waiting: Bool) {
        isWaiting = waiting
        fixes = []
        trimmed = false
        start = nil
        waitStartedAt = waiting ? Date() : nil
    }

    /// Departure is the last few fixes at riding speed, with the run-up
    /// carrying the rider `distance` from where they stood, or `fallbackDistance`
    /// from the start with no speed at all. Nil while still waiting.
    mutating func add(_ location: CLLocation, lastWalkingStepsAt: Date?) -> Departure? {
        fixes.append(location)
        if fixes.count > Self.maxFixes {
            fixes.removeFirst()
            trimmed = true
        }
        let poorFix = DistanceTracker.poorFixAccuracy
        if start == nil, location.horizontalAccuracy <= poorFix {
            start = location
        }

        // The run of fixes at bike pace that ends at this one.
        var runStart = fixes.count
        while runStart > 0, Self.isRunUpFix(fixes[runStart - 1]) { runStart -= 1 }
        let run = fixes[runStart...]
        let fast = run.suffix(Self.fastFixes).filter { $0.speed >= StopDetector.ridingSpeed }
        let origin: CLLocation? = runStart > 0 ? fixes[runStart - 1] : run.first
        let bySpeed =
            fast.count == Self.fastFixes
            && origin.map { location.distance(from: $0) >= Self.distance } == true
        let byDistance =
            !bySpeed && location.horizontalAccuracy <= poorFix
            && start.map { location.distance(from: $0) >= Self.fallbackDistance } == true
        guard bySpeed || byDistance else { return nil }

        var runUp: [CLLocation] = []
        var movingSince = location.timestamp
        var rolledFromStart = false
        if bySpeed {
            // Walking the step counter saw just before isn't part of the ride.
            var drawFrom = runStart
            if let lastWalkingStepsAt {
                while drawFrom < fixes.count - 1, fixes[drawFrom].timestamp <= lastWalkingStepsAt {
                    drawFrom += 1
                }
            }
            if drawFrom > 0, fixes[drawFrom - 1].horizontalAccuracy <= poorFix {
                runUp.append(fixes[drawFrom - 1])
            }
            runUp.append(contentsOf: fixes[drawFrom..<(fixes.count - 1)])
            movingSince = fixes[drawFrom].timestamp
            // Nothing before the run showed the rider standing, so they
            // started the ride already rolling.
            rolledFromStart =
                drawFrom == runStart && !trimmed
                && fixes[..<runStart].allSatisfy { $0.speedAccuracy < 0 }
            if rolledFromStart, let waitStartedAt { movingSince = waitStartedAt }
        } else if let start {
            runUp.append(start)
            let lastNearStart = fixes.last { $0.distance(from: start) < Self.distance }
            movingSince = lastNearStart?.timestamp ?? location.timestamp
        }

        let departure = Departure(
            bySpeed: bySpeed,
            runUp: runUp,
            movingSince: movingSince,
            rolledFromStart: rolledFromStart,
            heldFixes: fixes.count,
            waited: waitStartedAt.map { Date().timeIntervalSince($0) } ?? 0)
        isWaiting = false
        fixes = []
        start = nil
        return departure
    }

    private static func isRunUpFix(_ fix: CLLocation) -> Bool {
        fix.speedAccuracy >= 0 && fix.speed >= runUpSpeed
    }
}
