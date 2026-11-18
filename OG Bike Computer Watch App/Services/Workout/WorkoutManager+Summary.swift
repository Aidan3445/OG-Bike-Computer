//
//  WorkoutManager+Summary.swift
//  OG Bike Computer Watch App
//

import Foundation

/// Ride summaries for the phone and the watch summary screen, and the
/// export once a ride ends.
extension WorkoutManager {
    /// The route's name, or the time of day for a free ride.
    func currentRideName() -> String {
        if let routeName = initialRouteName { return routeName }
        switch Calendar.current.component(.hour, from: Date()) {
        case 5..<12: return "Morning Ride"
        case 12..<17: return "Afternoon Ride"
        case 17..<21: return "Evening Ride"
        default: return "Night Ride"
        }
    }

    /// The ride as it stands. Gain and loss default to the live totals.
    func makeRideSummary(
        id: UUID, date: Date, trackFilename: String,
        elevationGain: Double? = nil, elevationLoss: Double? = nil
    ) -> RideSummary {
        RideSummary(
            id: id,
            name: currentRideName(),
            activityType: currentActivity,
            date: date,
            elapsedTime: elapsedTime,
            movingTime: movingTime,
            distance: totalDistance,
            calories: activeCalories,
            elevationGain: elevationGain ?? liveElevationGain,
            elevationLoss: elevationLoss ?? liveElevationLoss,
            avgSpeed: averageSpeed,
            pointCount: recordedLocations.count,
            trackFilename: trackFilename,
            maxSpeed: maxSpeed > 0 ? maxSpeed : nil,
            avgPower: powerStat.count > 0 ? averagePower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            avgHeartRate: heartRateStat.count > 0 ? averageHeartRate : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
            highestElevation: highestElevation > -Double.greatestFiniteMagnitude
                ? highestElevation : nil,
            lowestElevation: lowestElevation < Double.greatestFiniteMagnitude
                ? lowestElevation : nil)
    }

    func makeWatchSummary(isHeld: Bool) -> WatchRideSummary {
        WatchRideSummary(
            distance: totalDistance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            avgSpeed: averageSpeed,
            maxSpeed: maxSpeed,
            elevationGain: liveElevationGain,
            calories: activeCalories,
            avgHeartRate: heartRateStat.count > 0 ? averageHeartRate : 0,
            maxHeartRate: maxHeartRate,
            avgPower: powerStat.count > 0 ? averagePower : 0,
            maxPower: maxPower,
            isHeld: isHeld
        )
    }

    func encodeTrack() -> Data {
        TrackEncoder.encodeV5(recordedLocations, heartRates: recordedHeartRates, powers: recordedPowers)
    }

    /// Sends the finished ride to the phone and clears the checkpoint.
    func exportAndTransferRide(savedToHealthKit: Bool) {
        // With no barometer, gain and loss are worked out again from the saved
        // track with the live threshold, so live and saved totals agree. The
        // 2 m floor keeps smoothing set to off from saving GPS noise.
        var gain = liveElevationGain
        var loss = liveElevationLoss
        if !AltimeterReader.isAvailable {
            let minDelta = max(ridePreferences.elevationSmoothing.elevMinDelta, 2.0)
            (gain, loss) = ElevationTracker.gpsGainLoss(of: recordedLocations, minDelta: minDelta)
        }

        let rideID = currentRideID ?? UUID()
        let trackFilename = "\(rideID.uuidString).track"
        let trackURL = FileManager.default.temporaryDirectory.appendingPathComponent(trackFilename)
        do {
            try encodeTrack().write(to: trackURL)
        } catch {
            print("Failed to write track data: \(error)")
            return
        }

        var summary = makeRideSummary(
            id: rideID, date: Date(), trackFilename: trackFilename,
            elevationGain: gain, elevationLoss: loss)
        if savedToHealthKit {
            summary.uploads = [
                ServiceUploadRecord(
                    service: .fitness, remoteID: "healthkit", uploadedAt: Date(), webURL: nil)
            ]
        }

        DispatchQueue.main.async {
            self.onRideCompleted?(summary)
            ConnectivityManager.shared.sendRide(summary: summary, trackURL: trackURL)
            RideCheckpointStore.delete()
        }
    }
}
