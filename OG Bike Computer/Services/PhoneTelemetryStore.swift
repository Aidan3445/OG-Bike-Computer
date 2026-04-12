//
//  PhoneTelemetryStore.swift
//  OG Bike Computer
//
//  Observable store of live ride telemetry received from the watch.
//  Updated by AppDelegate from HK mirrored session data. Observed by
//  RideControlView and used to resolve metric values on the phone.
//

#if os(iOS) && !WIDGET_EXTENSION
import Foundation
import Combine

class PhoneTelemetryStore: ObservableObject {
    static let shared = PhoneTelemetryStore()

    // Core ride stats
    @Published var elapsedTime: TimeInterval = 0
    @Published var movingTime: TimeInterval = 0
    @Published var totalDistance: Double = 0       // meters
    @Published var averageSpeed: Double = 0        // m/s
    @Published var currentSpeed: Double = 0        // m/s
    @Published var heartRate: Double = 0
    @Published var isPaused = false

    // Extended stats
    @Published var maxSpeed: Double = 0            // m/s
    @Published var averageHeartRate: Double = 0
    @Published var maxHeartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var currentElevation: Double = 0    // meters
    @Published var elevationGain: Double = 0       // meters
    @Published var elevationLoss: Double = 0       // meters
    @Published var highestElevation: Double = 0    // meters
    @Published var currentGrade: Double = 0        // percent
    @Published var estimatedPower: Double = 0      // watts

    // Navigation
    @Published var distanceToNextTurn: Double?     // meters
    @Published var nextTurnDirection: String?
    @Published var nextTurnIcon: String?
    @Published var nextTurnCue: String?
    @Published var routeDistanceRemaining: Double?

    // Off-route
    @Published var isOffRoute = false
    @Published var offRouteMessage: String?

    // Location
    @Published var riderLatitude: Double?
    @Published var riderLongitude: Double?

    private init() {}

    /// Update all fields from a telemetry payload dictionary.
    func update(from telemetry: [String: String]) {
        DispatchQueue.main.async { [self] in
            elapsedTime = Double(telemetry["elapsedTime"] ?? "") ?? elapsedTime
            movingTime = Double(telemetry["movingTime"] ?? "") ?? movingTime
            totalDistance = Double(telemetry["distance"] ?? "") ?? totalDistance
            averageSpeed = Double(telemetry["avgSpeed"] ?? "") ?? averageSpeed
            currentSpeed = Double(telemetry["speed"] ?? "") ?? currentSpeed
            heartRate = Double(telemetry["heartRate"] ?? "") ?? heartRate
            isPaused = telemetry["isPaused"] == "true"

            // Extended stats
            maxSpeed = Double(telemetry["maxSpeed"] ?? "") ?? maxSpeed
            averageHeartRate = Double(telemetry["avgHR"] ?? "") ?? averageHeartRate
            maxHeartRate = Double(telemetry["maxHR"] ?? "") ?? maxHeartRate
            activeCalories = Double(telemetry["calories"] ?? "") ?? activeCalories
            currentElevation = Double(telemetry["elevation"] ?? "") ?? currentElevation
            elevationGain = Double(telemetry["elevGain"] ?? "") ?? elevationGain
            elevationLoss = Double(telemetry["elevLoss"] ?? "") ?? elevationLoss
            highestElevation = Double(telemetry["highElev"] ?? "") ?? highestElevation
            currentGrade = Double(telemetry["grade"] ?? "") ?? currentGrade
            estimatedPower = Double(telemetry["power"] ?? "") ?? estimatedPower

            distanceToNextTurn = Double(telemetry["distToTurn"] ?? "")
            nextTurnDirection = telemetry["turnDir"]
            nextTurnIcon = telemetry["turnIcon"]
            nextTurnCue = telemetry["turnCue"]
            routeDistanceRemaining = Double(telemetry["routeRemaining"] ?? "")

            isOffRoute = telemetry["isOffRoute"] == "true"
            offRouteMessage = telemetry["offRouteMsg"]

            riderLatitude = Double(telemetry["lat"] ?? "")
            riderLongitude = Double(telemetry["lon"] ?? "")
        }
    }

    /// Resolve a MetricType into display strings using the latest telemetry.
    func resolve(_ type: MetricType) -> (value: String, label: String, unit: String) {
        let label = type.label
        let unit = type.unit
        let value: String

        switch type {
        case .speed:          value = formatSpeed(currentSpeed, false)
        case .averageSpeed:   value = formatSpeed(averageSpeed, false)
        case .maxSpeed:       value = maxSpeed > 0 ? formatSpeed(maxSpeed, false) : "--"
        case .distance:       value = formatDistance(totalDistance, false)
        case .distanceRemaining:
            value = routeDistanceRemaining.map { formatDistance($0, false) } ?? "--"
        case .elapsedTime:    value = formatTime(elapsedTime)
        case .movingTime:     value = formatTime(movingTime)
        case .heartRate:      value = heartRate > 0 ? formatHeartRate(heartRate) : "--"
        case .averageHeartRate: value = averageHeartRate > 0 ? formatHeartRate(averageHeartRate) : "--"
        case .maxHeartRate:   value = maxHeartRate > 0 ? formatHeartRate(maxHeartRate) : "--"
        case .calories:       value = activeCalories > 0 ? "\(Int(activeCalories))" : "--"
        case .currentElevation: value = formatElevation(currentElevation)
        case .elevationGain:  value = elevationGain > 0 ? formatElevation(elevationGain) : "--"
        case .elevationLoss:  value = elevationLoss > 0 ? formatElevation(elevationLoss) : "--"
        case .highestElevation: value = highestElevation > 0 ? formatElevation(highestElevation) : "--"
        case .grade:          value = currentGrade != 0 ? String(format: "%.1f%%", currentGrade) : "--"
        case .powerEstimate:  value = estimatedPower > 0 ? "\(Int(estimatedPower))W" : "--"
        case .nextTurnDistance:
            value = distanceToNextTurn.map { formatTurnDistance($0) } ?? "--"
        case .nextTurnDirection:
            value = nextTurnDirection ?? "--"
        case .heading:        value = "--"
        }

        return (value, label, unit)
    }

    func reset() {
        elapsedTime = 0
        movingTime = 0
        totalDistance = 0
        averageSpeed = 0
        currentSpeed = 0
        heartRate = 0
        isPaused = false
        maxSpeed = 0
        averageHeartRate = 0
        maxHeartRate = 0
        activeCalories = 0
        currentElevation = 0
        elevationGain = 0
        elevationLoss = 0
        highestElevation = 0
        currentGrade = 0
        estimatedPower = 0
        distanceToNextTurn = nil
        nextTurnDirection = nil
        nextTurnIcon = nil
        nextTurnCue = nil
        routeDistanceRemaining = nil
        isOffRoute = false
        offRouteMessage = nil
        riderLatitude = nil
        riderLongitude = nil
    }
}
#endif
