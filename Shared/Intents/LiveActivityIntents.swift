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
import Foundation

/// Helpers that read/write App Group defaults on the calling thread,
/// avoiding Sendable warnings from the global `UserDefaults` instance.
private enum RideCommandBridge {
    private static let defaults = UserDefaults(suiteName: "group.com.aidan3445.computa")

    static func readIsPaused() -> Bool {
        defaults?.bool(forKey: "isPaused") ?? false
    }

    static func send(_ command: String) {
        defaults?.set(command, forKey: "pendingRideCommand")
    }
}

// MARK: - Pause / Resume Toggle

struct PauseResumeRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "Pause or Resume Ride"
    static var description: IntentDescription = "Toggles pause/resume on the current ride."

    func perform() async throws -> some IntentResult {
        let isPaused = await RideCommandBridge.readIsPaused()
        await RideCommandBridge.send(isPaused ? "resume" : "pause")
        return .result()
    }
}

// MARK: - End Ride

struct EndRideIntent: LiveActivityIntent {
    static var title: LocalizedStringResource = "End Ride"
    static var description: IntentDescription = "Ends the current ride and saves it."

    func perform() async throws -> some IntentResult {
        await RideCommandBridge.send("end")
        return .result()
    }
}
#endif
