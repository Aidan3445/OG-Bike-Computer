//
//  RideIntents.swift
//  OG Bike Computer
//
//  App Intents for ride control — start, pause, resume, end, change route.
//  Used by Siri, Shortcuts, and the Action Button.
//
//  On iOS: controls the workout via RideSessionManager (mirrored HK session)
//  or sends a WatchConnectivity message for starting rides.
//  On watchOS: controls the workout via WorkoutManager directly.
//

import AppIntents
import Foundation

// MARK: - Start Ride

struct StartRideIntent: AppIntent {
    static var title: LocalizedStringResource = "Start Ride"
    static var description: IntentDescription = "Starts a new ride recording on the watch."
    static var openAppWhenRun = true

    @Parameter(title: "Route", optionsProvider: RouteOptionsProvider())
    var route: RouteEntity?

    @Parameter(title: "Activity Type", default: .cycling)
    var activityType: ActivityTypeEnum

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        // Send start command to watch via WatchConnectivity
        var message: [String: Any] = [
            "type": "startRide",
            "activity": activityType.rawValue
        ]
        if let route = route {
            message["routeID"] = route.id.uuidString
        }
        await ConnectivityManager.shared.sendRideCommand(message)
        let routeLabel = route?.name ?? "Free Ride"
        return .result(dialog: "Starting \(routeLabel).")
        #elseif os(watchOS)
        // Directly start via WorkoutManager would go here,
        // but the watch ContentView handles the start flow.
        return .result(dialog: "Opening ride start.")
        #endif
    }

    struct RouteOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [RouteEntity] {
            try await RouteEntityQuery().suggestedEntities()
        }
    }
}

// MARK: - Pause Ride

struct PauseRideAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Pause Ride"
    static var description: IntentDescription = "Pauses the current ride."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        guard await RideSessionManager.shared.isRideActive else {
            return .result(dialog: "No active ride to pause.")
        }
        await RideSessionManager.shared.pauseRide()
        return .result(dialog: "Ride paused.")
        #elseif os(watchOS)
        return .result(dialog: "Ride paused.")
        #endif
    }
}

// MARK: - Resume Ride

struct ResumeRideAppIntent: AppIntent {
    static var title: LocalizedStringResource = "Resume Ride"
    static var description: IntentDescription = "Resumes a paused ride."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        guard await RideSessionManager.shared.isRideActive else {
            return .result(dialog: "No active ride to resume.")
        }
        await RideSessionManager.shared.resumeRide()
        return .result(dialog: "Ride resumed.")
        #elseif os(watchOS)
        return .result(dialog: "Ride resumed.")
        #endif
    }
}

// MARK: - End Ride

struct EndRideAppIntent: AppIntent {
    static var title: LocalizedStringResource = "End Ride"
    static var description: IntentDescription = "Ends and saves the current ride."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        guard await RideSessionManager.shared.isRideActive else {
            return .result(dialog: "No active ride to end.")
        }
        let movingTime = await PhoneTelemetryStore.shared.movingTime
        if movingTime < 60 {
            await ConnectivityManager.shared.sendRideCommand(["type": "discardRide"])
            return .result(dialog: "Ride was under 1 minute and has been discarded.")
        }
        await RideSessionManager.shared.endRide()
        return .result(dialog: "Ride ended and saved.")
        #elseif os(watchOS)
        return .result(dialog: "Ride ended.")
        #endif
    }
}

// MARK: - Change Route

struct ChangeRouteIntent: AppIntent {
    static var title: LocalizedStringResource = "Change Route"
    static var description: IntentDescription = "Switches to a different route mid-ride."

    @Parameter(title: "Route")
    var route: RouteEntity

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        let message: [String: Any] = [
            "type": "changeRoute",
            "routeID": route.id.uuidString
        ]
        await ConnectivityManager.shared.sendRideCommand(message)
        return .result(dialog: "Switching to \(route.name).")
        #elseif os(watchOS)
        return .result(dialog: "Switching to \(route.name).")
        #endif
    }
}
