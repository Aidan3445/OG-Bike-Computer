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

    func startActivity(routeName: String?, isImperial: Bool) {
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
            isImperial: isImperial
        )

        let initialState = RideActivityAttributes.ContentState(
            elapsedTime: 0,
            movingTime: 0,
            totalDistance: 0,
            averageSpeed: 0,
            currentSpeed: 0,
            heartRate: nil,
            distanceToNextTurn: nil,
            nextTurnDirection: nil,
            nextTurnIcon: nil,
            nextTurnCue: nil,
            routeDistanceRemaining: nil,
            isOffRoute: false,
            offRouteMessage: nil,
            riderLatitude: nil,
            riderLongitude: nil
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
            distanceToNextTurn: Double(telemetry["distToTurn"] ?? ""),
            nextTurnDirection: telemetry["turnDir"],
            nextTurnIcon: telemetry["turnIcon"],
            nextTurnCue: telemetry["turnCue"],
            routeDistanceRemaining: Double(telemetry["routeRemaining"] ?? ""),
            isOffRoute: telemetry["isOffRoute"] == "true",
            offRouteMessage: telemetry["offRouteMsg"],
            riderLatitude: Double(telemetry["lat"] ?? ""),
            riderLongitude: Double(telemetry["lon"] ?? "")
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))

        Task {
            await activity.update(content)
        }
    }

    func endActivity() {
        // End ALL activities of this type — catches orphans from crashes or double-starts
        let allActivities = Activity<RideActivityAttributes>.activities
        if allActivities.isEmpty {
            print("[LiveActivity] No activities to end")
        } else {
            print("[LiveActivity] Ending \(allActivities.count) activity(ies)")
            for activity in allActivities {
                Task {
                    await activity.end(nil, dismissalPolicy: .immediate)
                }
            }
        }
        currentActivity = nil
    }
}
#endif
