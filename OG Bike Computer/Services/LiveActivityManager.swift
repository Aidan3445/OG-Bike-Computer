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
            rideStatus: .active
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
            rideStatus: .active
        )

        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(10))

        Task {
            await activity.update(content)
        }
    }

    /// How long the live activity should remain visible after the watch ends
    /// the underlying workout, so the rider has time to see the final state.
    static let postEndDismissalDelay: TimeInterval = 60
    /// Time the caller should wait after stamping a terminal status before
    /// tearing the workout session down. The rider is almost always paused
    /// when they tap Hold/End, so we lean on the long side — the goal is to
    /// guarantee the lock screen, Dynamic Island, and Ride/Held watch screens
    /// all visibly settle on the terminal state before HK teardown dismisses
    /// the activity.
    static let terminalRepaintDelay: TimeInterval = 2.5

    /// Push a "held" state to all activities WITHOUT dismissing them. The
    /// watch will resume the workout on its end, so we keep the activity
    /// alive but show a hand-raised banner instead of "Ride Complete".
    /// Awaits the ActivityKit update so the caller can rely on the new state
    /// being live before it tears down the HK session.
    func markHeld() async {
        await applyTerminalStatus(.held)
    }

    /// Push a "completed" state to all activities WITHOUT dismissing them.
    /// Call this as early as possible in the end-ride flow so the user sees a
    /// "Ride Complete" message immediately, before HK teardown / dismissal.
    /// Awaits the ActivityKit update so the caller can rely on the new state
    /// being live before it tears down the HK session.
    func markCompleted() async {
        await applyTerminalStatus(.completed)
    }

    func endActivity() {
        // End ALL activities of this type — catches orphans from crashes or
        // double-starts. Stamp a terminal status first so any lingering UI
        // shows the finish/hold message instead of stale pause/resume
        // controls, then schedule auto-dismissal. If `markHeld()` already
        // stamped the activity, preserve that — the rider intends to resume.
        let allActivities = Activity<RideActivityAttributes>.activities
        guard !allActivities.isEmpty else {
            print("[LiveActivity] No activities to end")
            currentActivity = nil
            return
        }
        print("[LiveActivity] Ending \(allActivities.count) activity(ies)")
        let dismissAt = Date().addingTimeInterval(Self.postEndDismissalDelay)
        for activity in allActivities {
            let finalState = clearedState(
                from: activity.content.state,
                override: activity.content.state.status == .held ? nil : .completed
            )
            Task {
                await activity.update(ActivityContent(state: finalState, staleDate: nil))
                await activity.end(
                    ActivityContent(state: finalState, staleDate: nil),
                    dismissalPolicy: .after(dismissAt)
                )
            }
        }
        currentActivity = nil
    }

    // MARK: - Helpers

    /// Stamp every running activity with `status` and clear the navigation /
    /// pause fields. Used for non-dismissing transitions (held / completed).
    /// Awaits all activity updates so callers can rely on the new state
    /// having been pushed before they proceed.
    private func applyTerminalStatus(_ status: RideStatus) async {
        let allActivities = Activity<RideActivityAttributes>.activities
        guard !allActivities.isEmpty else { return }
        await withTaskGroup(of: Void.self) { group in
            for activity in allActivities {
                let finalState = clearedState(from: activity.content.state, override: status)
                group.addTask {
                    await activity.update(ActivityContent(state: finalState, staleDate: nil))
                }
            }
        }
    }

    /// Reset the transient navigation / pause fields and apply `override` as
    /// the new status (or leave the status alone if `override` is nil).
    private func clearedState(
        from state: RideActivityAttributes.ContentState,
        override: RideStatus?
    ) -> RideActivityAttributes.ContentState {
        var s = state
        if let override { s.rideStatus = override }
        s.isPaused = false
        s.isAutoPaused = false
        s.isOffRoute = false
        s.nextTurnDirection = nil
        s.nextTurnIcon = nil
        s.nextTurnCue = nil
        s.distanceToNextTurn = nil
        return s
    }
}
#endif
