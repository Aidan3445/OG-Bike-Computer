//
//  ElevationTracker.swift
//  OG Bike Computer Watch App
//

import CoreLocation

/// Books climbing and descending. The barometer is the source when the watch
/// has one, since it's far less noisy than GPS altitude. GPS is the fallback.
struct ElevationTracker {
    var barometer = BarometerGainFilter()
    /// Climbing booked from the barometer this ride. A sim books it here for
    /// the trace without showing it.
    private(set) var baroGain: Double = 0
    private(set) var baroLoss: Double = 0
    private var gpsReference: Double?

    /// A continued ride carries its totals over.
    mutating func startBarometer(gain: Double, loss: Double) {
        baroGain = gain
        baroLoss = loss
    }

    mutating func ingestBarometer(_ reading: Double, at time: TimeInterval) -> BarometerGainFilter.Outcome {
        let outcome = barometer.ingest(reading, at: time)
        switch outcome {
        case .gain(let climb): baroGain += climb
        case .loss(let drop): baroLoss += drop
        case .skipped: break
        }
        return outcome
    }

    /// Height change booked from a GPS altitude: positive for a climb,
    /// negative for a descent, 0 while it's within `minDelta` of the last
    /// booked altitude.
    mutating func gpsChange(altitude: Double, minDelta: Double) -> Double {
        guard let ref = gpsReference else {
            gpsReference = altitude
            return 0
        }
        let delta = altitude - ref
        guard abs(delta) > minDelta else { return 0 }
        gpsReference = altitude
        return delta
    }

    mutating func resetGPS() {
        gpsReference = nil
    }

    /// Gain and loss over a saved track, for watches with no barometer.
    static func gpsGainLoss(of locations: [CLLocation], minDelta: Double) -> (gain: Double, loss: Double) {
        guard locations.count > 1 else { return (0, 0) }
        var gain: Double = 0
        var loss: Double = 0
        var ref = locations[0].altitude
        for location in locations.dropFirst() {
            guard location.verticalAccuracy >= 0, location.verticalAccuracy < 10 else { continue }
            let delta = location.altitude - ref
            if delta > minDelta {
                gain += delta
                ref = location.altitude
            } else if delta < -minDelta {
                loss -= delta
                ref = location.altitude
            }
        }
        return (gain, loss)
    }
}
