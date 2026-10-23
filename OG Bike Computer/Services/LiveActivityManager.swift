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

    /// Latched the moment we apply a terminal banner (held / completed) so
    /// telemetry ticks racing in afterward can't rewrite `rideStatus` back to
    /// `.active`. We can't rely on reading `activity.content.state.status` for
    /// this because `activity.content` updates asynchronously — after
    /// `await activity.update(...)` returns, the local proxy may still read
    /// the previous status for a brief window. The flag is cleared when a new
    /// activity starts.
    private var terminalStateLatched = false

    /// Coalescing buffer for telemetry-driven updates. ActivityKit budgets
    /// local updates — firing an unserialized `activity.update` Task for
    /// every 1–3s telemetry tick both races out-of-order and burns through
    /// that budget until the system throttles the activity into permanent
    /// staleness on long rides. Only one update is in flight at a time;
    /// ticks that land mid-flight overwrite `pendingState` and the newest
    /// one is pushed when the in-flight update returns.
    private var pendingState: RideActivityAttributes.ContentState?
    private var lastPushedState: RideActivityAttributes.ContentState?
    private var isPushing = false

    /// How long a pushed state stays fresh before the widget switches to its
    /// "no signal" treatment. Long enough to ride out watch↔phone hiccups,
    /// short enough that a genuinely dead link is visible to the rider.
    private static let staleInterval: TimeInterval = 60

    private init() {}

    // MARK: - Lifecycle

    func startActivity(
        routeName: String?,
        isImperial: Bool,
        statSlots: [String] = LiveActivitySlot.defaultSlots.map(\.metricType.rawValue),
        showStatsInIsland: Bool = true,
        distanceRemainingFallback: String = MetricType.distance.rawValue
    ) {
        let authInfo = ActivityAuthorizationInfo()
        print("[LiveActivity] Authorization check: areActivitiesEnabled=\(authInfo.areActivitiesEnabled), frequentPushesEnabled=\(authInfo.frequentPushesEnabled)")
        guard authInfo.areActivitiesEnabled else {
            print("[LiveActivity] Not authorized — activities disabled on system or no entitlement")
            return
        }

        // Fresh activity — clear the terminal latch from any prior ride so
        // telemetry can flow again.
        terminalStateLatched = false
        pendingState = nil
        lastPushedState = nil

        // Leftovers from a previous ride (terminal banner still on screen, or
        // an orphan from a crash) carry stale attributes — replace, don't
        // adopt. They're ended after the new request succeeds so the rider
        // never briefly has zero surfaces.
        let leftovers = Activity<RideActivityAttributes>.activities

        let attributes = RideActivityAttributes(
            routeName: routeName,
            startTime: Date(),
            isImperial: isImperial,
            statSlots: statSlots,
            showStatsInIsland: showStatsInIsland,
            distanceRemainingFallback: distanceRemainingFallback
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
            missedTurnLabel: nil,
            missedTurnCue: nil,
            riderLatitude: nil,
            riderLongitude: nil,
            rideStatus: .active
        )

        let content = ActivityContent(state: initialState, staleDate: Date().addingTimeInterval(Self.staleInterval))

        do {
            currentActivity = try Activity.request(
                attributes: attributes,
                content: content,
                pushType: nil
            )
            print("[LiveActivity] Started: \(currentActivity?.id ?? "nil") — ending \(leftovers.count) leftover(s)")
            for activity in leftovers {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
        } catch {
            // Requesting can fail when HealthKit relaunches us in the
            // background on a mirroring reconnect. Fall back to adopting a
            // leftover so the rider keeps a live surface, and reset its state
            // to active so a stale terminal banner doesn't linger until the
            // first telemetry tick.
            print("[LiveActivity] Failed to start: \(error)")
            guard let adopted = leftovers.first else { return }
            print("[LiveActivity] Adopting leftover activity \(adopted.id) instead")
            currentActivity = adopted
            for activity in leftovers.dropFirst() {
                Task { await activity.end(nil, dismissalPolicy: .immediate) }
            }
            let reset = clearedState(from: adopted.content.state, override: .active)
            Task {
                await adopted.update(ActivityContent(state: reset, staleDate: Date().addingTimeInterval(Self.staleInterval)))
            }
        }
    }

    func update(from telemetry: [String: String]) {
        guard let activity = currentActivity else { return }

        // Once the LA is in a terminal state (held / completed) we've already
        // optimistically stamped a banner the rider is meant to see while the
        // watch finishes tearing down. Telemetry keeps flowing for a beat
        // after that — letting it through would rewrite `rideStatus` back to
        // `.active` and flicker the banner off mid-teardown.
        guard !terminalStateLatched else { return }

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
            missedTurnLabel: telemetry["missedTurnLabel"],
            missedTurnCue: telemetry["missedTurnCue"],
            riderLatitude: Double(telemetry["lat"] ?? ""),
            riderLongitude: Double(telemetry["lon"] ?? ""),
            rideStatus: .active
        )

        pendingState = state
        pushPendingUpdate()
    }

    /// Drain the coalescing buffer: push the newest pending state if no
    /// update is already in flight, then re-check when it returns.
    private func pushPendingUpdate() {
        guard !isPushing, let state = pendingState else { return }
        pendingState = nil
        guard state != lastPushedState, let activity = currentActivity else { return }
        isPushing = true
        lastPushedState = state
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(Self.staleInterval))
        Task {
            await activity.update(content)
            isPushing = false
            pushPendingUpdate()
        }
    }

    /// How long a terminal banner stays visible after the app is foregrounded
    /// with no ride running, before `cleanupLeftoverActivities` dismisses it.
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

    /// Push a "discarded" state to all activities WITHOUT dismissing them.
    /// Used for short-ride discards so the rider sees a red "Ride Discarded"
    /// banner instead of a generic "Ride Complete" before teardown.
    func markDiscarded() async {
        await applyTerminalStatus(.discarded)
    }

    /// Stamp a terminal banner on every running activity when the workout
    /// tears down — WITHOUT ending them. The activity outlives the workout
    /// session: calling `end()` here raced app suspension (the update/end
    /// Tasks often never ran once the HK session died), so the final state
    /// frequently never displayed. Leftovers are cleared when the next ride
    /// starts (`startActivity` replaces them), when the app is next
    /// foregrounded with no ride running (`cleanupLeftoverActivities`), or
    /// by the rider swiping the banner away.
    func finalizeAfterWorkoutEnd() {
        let allActivities = Activity<RideActivityAttributes>.activities
        currentActivity = nil
        pendingState = nil
        guard !allActivities.isEmpty else {
            print("[LiveActivity] No activities to finalize")
            terminalStateLatched = false
            return
        }
        // Latch so any straggler telemetry can't repaint the banner active.
        terminalStateLatched = true
        print("[LiveActivity] Finalizing \(allActivities.count) activity(ies)")
        for activity in allActivities {
            // Preserve any non-active terminal stamp that markHeld /
            // markDiscarded / markCompleted already applied. Only default to
            // .completed when no terminal flow has run yet (e.g. the watch
            // ended the ride without going through the iPhone control path).
            let existing = activity.content.state.status
            let override: RideStatus? = (existing == .active || existing == .inactive)
                ? .completed
                : nil
            let finalState = clearedState(from: activity.content.state, override: override)
            Task {
                await activity.update(ActivityContent(state: finalState, staleDate: nil))
            }
        }
    }

    /// Dismiss terminal banners the rider has implicitly seen. Called when
    /// the app is foregrounded with no ride running. Only completed /
    /// discarded banners are ended — held rides keep their banner up as the
    /// resume affordance, and anything still stamped `.active` is left alone
    /// in case a mirroring reconnect is about to adopt it.
    func cleanupLeftoverActivities() {
        let dismissAt = Date().addingTimeInterval(Self.postEndDismissalDelay)
        for activity in Activity<RideActivityAttributes>.activities {
            let status = activity.content.state.status
            guard status == .completed || status == .discarded else { continue }
            print("[LiveActivity] Cleaning up leftover \(status.rawValue) activity \(activity.id)")
            let content = ActivityContent(state: activity.content.state, staleDate: nil)
            Task {
                await activity.end(content, dismissalPolicy: .after(dismissAt))
            }
        }
    }

    // MARK: - Helpers

    /// Stamp every running activity with `status` and clear the navigation /
    /// pause fields. Used for non-dismissing transitions (held / completed).
    /// Awaits all activity updates so callers can rely on the new state
    /// having been pushed before they proceed.
    private func applyTerminalStatus(_ status: RideStatus) async {
        let allActivities = Activity<RideActivityAttributes>.activities
        guard !allActivities.isEmpty else { return }
        // Latch BEFORE awaiting so any telemetry tick racing in during the
        // ActivityKit round-trip sees the latch and bails. If we set it
        // after, the in-flight update would lose to the next telemetry write.
        // Drop any buffered tick too — the coalescer would otherwise push it
        // after the terminal update returns.
        terminalStateLatched = true
        pendingState = nil
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
        s.missedTurnLabel = nil
        s.missedTurnCue = nil
        return s
    }
}
#endif
