//
//  LiveActivityManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

#if canImport(ActivityKit)
import ActivityKit
import Foundation

class LiveActivityManager {
    static let shared = LiveActivityManager()

    private var currentActivity: Activity<RideActivityAttributes>?

    private init() {}

    // MARK: - Lifecycle

    func startActivity(routeName: String?, isImperial: Bool, statSlots: [String] = LiveActivitySlot.defaultSlots.map(\.metricType.rawValue)) {
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] Authorization check: areActivitiesEnabled=\(authInfo.areActivitiesEnabled), frequentPushesEnabled=\(authInfo.frequentPushesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] Not authorized — activities disabled on system or no entitlement")
            return
        }

        // Check for existing activities — adopt one if found, end extras
        let existing = Activity<RideActivityAttributes>.activities
        if !existing.isEmpty {
            print("[LiveActivity] Found \(existing.count) existing activity(ies) — adopting first, ending extras")
            currentActivity = existing.first
            for activity in existing.dropFirst() {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            return
        }

        let attributes = RideActivityAttributes(
            routeName: routeName,
            startTime: Date(),
            isImperial: isImperial,
            statSlots: statSlots
        )

        let initialState = RideActivityAttributes.ContentState(
            elapsedTime: 0,
            movingTime: 0,
            totalDistance: 0,
            averageSpeed: 0,
            currentSpeed: 0,
            heartRate: nil,
            maxSpeed: nil,
            averageHeartRate: nil,
            maxHeartRate: nil,
            activeCalories: nil,
            currentElevation: nil,
            elevationGain: nil,
            elevationLoss: nil,
            highestElevation: nil,
            currentGrade: nil,
            estimatedPower: nil,
            distanceToNextTurn: nil,
            nextTurnDirection: nil,
            nextTurnIcon: nil,
            nextTurnCue: nil,
            routeDistanceRemaining: nil,
            isPaused: false,
            isAutoPaused: false,
            isOffRoute: false,
            distanceOffRoute: nil,
            riderLatitude: nil,
            riderLongitude: nil,
            rideStatus: "active"
        )

        let content = ActivityContent(state: initialState, staleDate: nil)

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("[LiveActivity] Started: \(currentActivity?.id ?? "nil")")
        } catch {
            print("[LiveActivity] Failed to start: \(error)")
        }
    }

    func update(from telemetry: [String: String]) {
        guard let activity = currentActivity else { return }

        let state = RideActivityAttributes.ContentState(
            elapsedTime: Double(telemetry["elapsedTime"] ?? "") ?? 0,
            movingTime: Double(telemetry["movingTime"] ?? "") ?? 0,
            totalDistance: Double(telemetry["distance"] ?? "") ?? 0,
            averageSpeed: Double(telemetry["avgSpeed"] ?? "") ?? 0,
            currentSpeed: Double(telemetry["speed"] ?? "") ?? 0,
            heartRate: Double(telemetry["heartRate"] ?? ""),
            maxSpeed: Double(telemetry["maxSpeed"] ?? ""),
            averageHeartRate: Double(telemetry["avgHR"] ?? ""),
            maxHeartRate: Double(telemetry["maxHR"] ?? ""),
            activeCalories: Double(telemetry["calories"] ?? ""),
            currentElevation: Double(telemetry["elevation"] ?? ""),
            elevationGain: Double(telemetry["elevGain"] ?? ""),
            elevationLoss: Double(telemetry["elevLoss"] ?? ""),
            highestElevation: Double(telemetry["highElev"] ?? ""),
            currentGrade: Double(telemetry["grade"] ?? ""),
            estimatedPower: Double(telemetry["power"] ?? ""),
            distanceToNextTurn: Double(telemetry["distToTurn"] ?? ""),
            nextTurnDirection: telemetry["turnDir"],
            nextTurnIcon: telemetry["turnIcon"],
            nextTurnCue: telemetry["turnCue"],
            routeDistanceRemaining: Double(telemetry["routeRemaining"] ?? ""),
            isPaused: telemetry["isPaused"] == "true",
            isAutoPaused: telemetry["isAutoPaused"] == "true",
            isOffRoute: telemetry["isOffRoute"] == "true",
            distanceOffRoute: Double(telemetry["distOffRoute"] ?? ""),
            riderLatitude: Double(telemetry["lat"] ?? ""),
            riderLongitude: Double(telemetry["lon"] ?? ""),
            rideStatus: "active"
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))

        Task {
            await activity.update(content)
        }
    }

    /// Push a "completed" state to all activities WITHOUT dismissing them.
    /// Call this as early as possible in the end-ride flow so the user sees a
    /// "Ride Complete" message immediately, before HK teardown / dismissal.
    func markCompleted() {
        let allActivities = Activity<RideActivityAttributes>.activities
        guard !allActivities.isEmpty else { return }
        for activity in allActivities {
            var state = activity.content.state
            state.rideStatus = "completed"
            state.isPaused = false
            state.isAutoPaused = false
            state.isOffRoute = false
            state.nextTurnDirection = nil
            state.nextTurnIcon = nil
            state.nextTurnCue = nil
            state.distanceToNextTurn = nil
            let finalState = state
            Task {
                await activity.update(ActivityContent(state: finalState, staleDate: nil))
            }
        }
    }

    func endActivity() {
        // End ALL activities of this type — catches orphans from crashes or double-starts.
        // Push a "completed" state first so any lingering UI shows a finish message
        // instead of the stale pause/resume controls, then schedule auto-dismissal.
        let allActivities = Activity<RideActivityAttributes>.activities
        if allActivities.isEmpty {
            print("[LiveActivity] No activities to end")
        } else {
            print("[LiveActivity] Ending \(allActivities.count) activity(ies)")
            let dismissAt = Date().addingTimeInterval(60)
            for activity in allActivities {
                Task {
                    var finalState = activity.content.state
                    finalState.rideStatus = "completed"
                    finalState.isPaused = false
                    finalState.isAutoPaused = false
                    finalState.isOffRoute = false
                    finalState.nextTurnDirection = nil
                    finalState.nextTurnIcon = nil
                    finalState.nextTurnCue = nil
                    finalState.distanceToNextTurn = nil
                    await activity.update(ActivityContent(state: finalState, staleDate: nil))
                    await activity.end(
                        ActivityContent(state: finalState, staleDate: nil),
                        dismissalPolicy: .after(dismissAt)
                    )
                }
            }
        }
        currentActivity = nil
    }
}
#endif
