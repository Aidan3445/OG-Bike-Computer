//
//  PositionBuffer.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// The last few seconds of fixes, for a ground speed worked out from where
/// the rider actually went. `CLLocation.speed` can freeze at a stale value
/// when stopped, so pause and resume decisions trust this instead.
struct PositionBuffer {
    static let window: TimeInterval = 8

    private var entries: [(loc: CLLocation, t: Date)] = []

    /// The buffer needs to span most of the window before its numbers mean anything.
    var isReady: Bool { span >= Self.window * 0.6 }

    /// Meters from the oldest fix to the newest, or 0 until ready.
    var displacement: Double {
        guard isReady, let first = entries.first, let last = entries.last else { return 0 }
        return last.loc.distance(from: first.loc)
    }

    /// Meters per second from the oldest fix to the newest, or 0 until ready.
    var speed: Double {
        guard isReady, let first = entries.first, let last = entries.last else { return 0 }
        return last.loc.distance(from: first.loc) / span
    }

    private var span: TimeInterval {
        guard let first = entries.first, let last = entries.last else { return 0 }
        return last.t.timeIntervalSince(first.t)
    }

    mutating func append(_ location: CLLocation) {
        entries.append((loc: location, t: Date()))
        evictStale()
    }

    /// Also runs every second, so the buffer empties out when GPS goes quiet.
    mutating func evictStale() {
        let cutoff = Date().addingTimeInterval(-Self.window)
        while let first = entries.first, first.t < cutoff {
            entries.removeFirst()
        }
    }

    mutating func removeFixes(before date: Date) {
        entries.removeAll { $0.loc.timestamp < date }
    }

    mutating func removeAll() {
        entries = []
    }
}
