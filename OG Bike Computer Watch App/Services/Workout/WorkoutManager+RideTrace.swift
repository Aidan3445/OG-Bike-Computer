//
//  WorkoutManager+RideTrace.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import CoreMotion
import HealthKit
import WatchKit

/// The ride's diagnostic CSVs. They're nil when diagnostics are off.
struct RideTraceFiles {
    static let fixesHeader = [
        "fixTime", "receivedAt", "lat", "lon", "hAcc", "altitude", "vAcc",
        "speed", "speedAcc", "course", "sinceLastFix", "rejectedBefore",
        "stateBefore", "stateAfter", "silentProbe",
        "bufferSpeedMPH", "bufferDisplacement", "clSpeedMPH",
        "slowSamples", "fastSamples", "tentativeDistance",
        "recorded", "distanceAdded", "gapSkipped",
        "gpsMode", "desiredAccuracy", "distanceFilter",
        "staleBefore", "poorFixHeld",
    ]
    static let ticksHeader = [
        "time", "appState", "hkState", "isPaused", "autoPauseState", "silentProbe",
        "sinceLastFix", "movingTime", "elapsedTime", "totalDistance",
        "mirroringReady", "earlyTelemetry", "sinceTelemetrySend", "telemetryResult",
        "skippedTelemetrySends", "standingStill", "walking", "steps", "stepCadence",
        "awaitingStart", "rideOffHeld", "battery",
    ]
    static let baroHeader = [
        "time", "source", "relativeAltitude", "reference", "delta",
        "accumulated", "skipReason", "gainBooked", "lossBooked",
        "currentElevation", "liveGain", "liveLoss",
        "absAltitude", "absAccuracy", "absPrecision", "sensorTime",
    ]

    private(set) var fixes: DiagnosticsCSV?
    private(set) var ticks: DiagnosticsCSV?
    private(set) var baro: DiagnosticsCSV?

    /// A continued held ride reopens the same files and appends.
    mutating func open(rideID: UUID) {
        fixes = DiagnosticsCSV(rideID: rideID, kind: "fixes", header: Self.fixesHeader)
        ticks = DiagnosticsCSV(rideID: rideID, kind: "ticks", header: Self.ticksHeader)
        baro = DiagnosticsCSV(rideID: rideID, kind: "baro", header: Self.baroHeader)
    }

    /// Writes everything out before the ride transfer sends the files.
    mutating func close() {
        fixes?.close()
        ticks?.close()
        baro?.close()
        fixes = nil
        ticks = nil
        baro = nil
    }
}

extension WorkoutManager {
    static func mph(_ metersPerSecond: Double) -> String {
        String(format: "%.1f", metersPerSecond * 2.23694)
    }

    func openTraceFiles(rideID: UUID) {
        trace.open(rideID: rideID)
        DiagnosticsLog.event("Rules", rulesDescription)
        rejectedFixesSinceLast = 0
        staleFixesSinceLast = 0
        skippedTelemetrySends = 0
        lastTelemetrySendAt = nil
        lastTelemetryResult = ""
    }

    func closeTraceFiles() {
        trace.close()
    }

    /// Every threshold the ride runs with, logged at the start of each segment.
    private var rulesDescription: String {
        let autoPause = ridePreferences.autoPause
        let walking =
            "\(String(format: "%.1f", StopDetector.walkingCadence))steps/s,\(Int(StopDetector.walkingStepsWindow))s+noRiding\(Int(StopDetector.walkingRidingWindow))s"
        let start =
            "\(DepartureDetector.fastFixes)fixes@\(Self.mph(StopDetector.ridingSpeed))mph+\(Int(DepartureDetector.distance))m|\(Int(DepartureDetector.fallbackDistance))m"
        let rideOff =
            "\(RideOffCheck.fixes)fixes,heading\(Int(RideOffCheck.headingSpread)),\(Int(RideOffCheck.distance))m,speedAcc<=\(RideOffCheck.speedAccuracyCap)|\(RideOffCheck.vagueSpeedFactor)x,window\(Int(RideOffCheck.window))s,push=\(Int(StopTracker.pushDistance))m,near\(Int(StopTracker.nearby))m"
        return [
            "mode=\(autoPause.mode.rawValue)",
            "pauseSpeed=\(Self.mph(autoPause.speedThreshold))mph",
            "positionPause=\(Self.mph(positionPauseSpeed))mph",
            "standingStill=\(Self.mph(StopDetector.standingStillSpeed))mph",
            "poorFix>\(Int(DistanceTracker.poorFixAccuracy))m",
            "maxFixAge=\(Int(Self.maxFixAge))s",
            "baroStop=freeze",
            "baroRiding=\(Self.mph(StopDetector.ridingSpeed))mph/\(Int(StopDetector.ridingWindow))s",
            "baroFloor=\(elevationTracker.barometer.noiseFloor)m",
            "walking=\(walking)",
            "pedometer=\(StopDetector.isStepCountingAvailable)",
            "rideOff=\(rideOff)",
            "stopFloor=\(Self.mph(StopTracker.floor))mph",
            "backfill=\(Int(Self.maxBackfillSpeed))m/s|\(Int(Self.maxBackfillGap))m",
            "start=\(start)",
            "waiting=\(departureDetector.isWaiting)",
        ].joined(separator: " ")
    }

    func traceFix(
        _ location: CLLocation, receivedAt: Date, previousFix: CLLocation?,
        stateBefore: AutoPauseState, recorded: Bool, distanceAdded: Double,
        gapSkipped: Bool, gpsMode: BatteryManager.GPSMode?
    ) {
        guard let csv = trace.fixes else { return }
        csv.append([
            location.timestamp, receivedAt,
            location.coordinate.latitude, location.coordinate.longitude,
            location.horizontalAccuracy, location.altitude, location.verticalAccuracy,
            location.speed, location.speedAccuracy, location.course,
            previousFix.map { location.timestamp.timeIntervalSince($0.timestamp) },
            rejectedFixesSinceLast,
            "\(stateBefore)", "\(autoPauseState)", isSilentProbe,
            traceBufferSpeedMPH, traceBufferDisplacement, traceCLSpeedMPH,
            slowSampleCount, tentative.fastSampleCount, tentative.distance,
            recorded, distanceAdded, gapSkipped,
            gpsMode?.rawValue, locationManager.desiredAccuracy, locationManager.distanceFilter,
            staleFixesSinceLast, distanceTracker.isHoldingPoorFix,
        ])
        rejectedFixesSinceLast = 0
        staleFixesSinceLast = 0
    }

    func traceTick() {
        guard let csv = trace.ticks else { return }
        let now = Date()
        let appState: String
        switch WKApplication.shared().applicationState {
        case .active: appState = "active"
        case .inactive: appState = "inactive"
        case .background: appState = "background"
        @unknown default: appState = "unknown"
        }
        // For comparing what each stop mode costs.
        let device = WKInterfaceDevice.current()
        if !device.isBatteryMonitoringEnabled { device.isBatteryMonitoringEnabled = true }
        let battery = device.batteryLevel >= 0 ? Double(device.batteryLevel) : nil
        csv.append([
            now, appState, session?.state.rawValue, isPaused, "\(autoPauseState)", isSilentProbe,
            lastLocationUpdateAt.map { now.timeIntervalSince($0) },
            movingTime, elapsedTime, totalDistance,
            isMirroringReady, earlyTelemetrySessionID != nil,
            lastTelemetrySendAt.map { now.timeIntervalSince($0) }, lastTelemetryResult,
            skippedTelemetrySends, isStandingStill, stopDetector.isWalking,
            stopDetector.isPedometerRunning ? stopDetector.stepCount : nil,
            stopDetector.stepCadence, departureDetector.isWaiting, stopTracker.held.count,
            battery,
        ])
    }

    func traceBarometer(
        relativeAltitude: Double, reference: Double?, skipReason: String?,
        gainBooked: Double, lossBooked: Double, sensorTime: TimeInterval
    ) {
        guard let csv = trace.baro else { return }
        csv.append([
            Date(), "relative", relativeAltitude, reference,
            reference.map { relativeAltitude - $0 },
            skipReason == nil, skipReason, gainBooked, lossBooked,
            currentElevation, liveElevationGain, liveElevationLoss,
            nil, nil, nil, sensorTime,
        ])
    }

    /// Absolute altitude is traced alongside the relative readings to compare
    /// against. It never feeds the live numbers.
    func traceAbsoluteAltitude(_ data: CMAbsoluteAltitudeData) {
        guard let csv = trace.baro else { return }
        csv.append([
            Date(), "absolute", nil, nil, nil, nil, nil, nil, nil,
            currentElevation, liveElevationGain, liveElevationLoss,
            data.altitude, data.accuracy, data.precision, data.timestamp,
        ])
    }
}
