//
//  LiveActivityIntents.swift
//  OG Bike Computer
//
//  App Intents for controlling a ride directly from the Live Activity widget.
//  These conform to LiveActivityIntent so they can be used in Button() within
//  the widget's SwiftUI layout.
//
//  On the iOS app target, they control the workout via the mirrored HK session.
//  On the widget extension target, they write commands to App Group UserDefaults
//  so the host app can pick them up.
//

#if canImport(ActivityKit)
import AppIntents
import ActivityKit
import Foundation

/// Helpers that read/write App Group defaults on the calling thread,
/// avoiding Sendable warnings from the global `UserDefaults` instance.
private enum RideCommandBridge {
    private static let defaults = UserDefaults(suiteName: "group.com.aidan3445.computa")

    static func readIsPaused() -> Bool {
        defaults?.bool(forKey: "isPaused") ?? false
    }

    static func readMovingTime() -> TimeInterval {
        defaults?.double(forKey: "movingTime") ?? 0
    }

    static func send(_ command: String) {
        defaults?.set(command, forKey: "pendingRideCommand")
    }

    /// Write optimistic state so the widget extension's next render reflects
    /// the action immediately (before the main app processes the command).
    static func writeOptimisticIsPaused(_ isPaused: Bool) {
        defaults?.set(isPaused, forKey: "isPaused")
    }
}

/// Push an optimistic `isPaused` flip to the live activity so the widget
/// updates instantly without waiting for the main app round-trip.
private func optimisticallyUpdateLiveActivity(isPaused: Bool) async {
    guard let activity = Activity<RideActivityAttributes>.activities.first else { return }
    var newState = activity.contentState
    newState.isPaused = isPaused
    await activity.update(ActivityContent(state: newState, staleDate: nil))
}

// MARK: - Pause / Resume Toggle

struct PauseResumeRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Ride"
    static var description: IntentDescription = "Toggles pause/resume on the current ride."
    
    // Hide from shortcuts/automations
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let isPaused = await RideCommandBridge.readIsPaused()
        let nowPaused = !isPaused
        // Optimistic: update shared state and live activity immediately
        await RideCommandBridge.writeOptimisticIsPaused(nowPaused)
        await optimisticallyUpdateLiveActivity(isPaused: nowPaused)
        // Queue the command for the main app to execute
        await RideCommandBridge.send(isPaused ? "resume" : "pause")
        return .result()
    }
}

// MARK: - Hold Ride

struct HoldRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Hold Ride"
    static var description: IntentDescription = "Puts the current ride on hold to continue later."

    // Hide from shortcuts/automations
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        await RideCommandBridge.send("hold")
        return .result(dialog: "Ride on hold. Resume it later from the app or ride list.")
    }
}

// MARK: - End Ride

struct EndRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Ride"
    static var description: IntentDescription = "Ends the current ride and saves it."
    
    // Hide from shortcuts/automations
    static var isDiscoverable: Bool = false

    func perform() async throws -> some IntentResult {
        let movingTime = await RideCommandBridge.readMovingTime()
        if movingTime < 60 {
            // Short ride — tell the app to discard both HK workout and app recording
            await RideCommandBridge.send("discard")
            return .result(dialog: "Ride was under 1 minute and has been discarded.")
        } else {
            await RideCommandBridge.send("end")
            return .result(dialog: "Ride ended and saved.")
        }
    }
}
#endif
