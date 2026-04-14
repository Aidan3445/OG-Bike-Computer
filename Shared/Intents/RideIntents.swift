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
#if canImport(HealthKit)
import HealthKit
#endif
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "AppIntents")

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
        await logger.info("Start Ride Intent")

        #if os(iOS)
        // Two-pronged approach:
        // 1. Send route + start command via WC (fire-and-forget, may arrive late)
        // 2. Launch watch app via HKHealthStore.startWatchApp (reliable foreground)
        //
        // The watch has handlers for both paths, guarded by !workout.isActive,
        // so only the first to execute starts the ride.

        // (1) WC message — carries route ID, best-effort
        var message: [String: Any] = [
            "type": "startRide",
            "activity": activityType.rawValue
        ]
        if let route = route {
            message["routeID"] = route.id.uuidString
        }
        
        if let routeName = route?.name, let routeId = route?.id {
            let onWatch = await MainActor.run {
                ConnectivityManager.shared.routeNamesOnWatch.contains(routeName)
            }
            
            if !onWatch {
                guard let fullRoute = await loadRoute(id: routeId) else {
                    return .result(dialog: "Could not load route \"\(routeName)\".")
                }
                
                await withCheckedContinuation { continuation in
                    Task { @MainActor in
                        ConnectivityManager.shared.sendRoute(
                            fullRoute,
                            pendingAction: "changeRoute"
                        ) { _ in
                            ConnectivityManager.shared.sendRideCommand(message)
                            
                            continuation.resume()
                        }
                    }
                }
            }
        }
        
        await ConnectivityManager.shared.sendRideCommand(message)

        // (2) HKHealthStore.startWatchApp — guaranteed to launch + foreground watch
        let config = HKWorkoutConfiguration()
        config.activityType = await activityType.activityType.hkType
        config.locationType = .outdoor

        let healthStore = HKHealthStore()
        healthStore.startWatchApp(with: config) {_,_ in
            logger.info("Workout started from APP INTENT")
        }

        let routeLabel = route?.name ?? "Free Ride"
        return .result(dialog: "Starting \(routeLabel).")

        #elseif os(watchOS)
        // On watchOS, Siri/Shortcuts routes through WatchStartWorkoutIntent
        // (StartWorkoutIntent protocol) which has system-level foreground
        // guarantees. This generic AppIntent shouldn't be the entry point,
        // but handle it gracefully if it is.
        await logger.warning("StartRideIntent invoked on watchOS — prefer WatchStartWorkoutIntent for foreground guarantees")
        return .result(dialog: "Use the Start Ride shortcut for best results.")
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
        
        let onWatch = await MainActor.run {
            ConnectivityManager.shared.routeNamesOnWatch.contains(route.name)
        }

        if onWatch {
            await MainActor.run {
                ConnectivityManager.shared.sendRideCommand(message)
            }
        } else {
            guard let fullRoute = await loadRoute(id: route.id) else {
                return .result(dialog: "Could not load route \"\(route.name)\".")
            }
            
            await withCheckedContinuation { continuation in
                Task { @MainActor in
                    ConnectivityManager.shared.sendRoute(
                        fullRoute,
                        pendingAction: "changeRoute"
                    ) { _ in
                        ConnectivityManager.shared.sendRideCommand(message)
                        
                        continuation.resume()
                    }
                }
            }
            
            return .result(dialog: "Sent route \"\(route.name)\" to watch.")
        }

        return .result(dialog: "Switching to \(route.name).")

        #elseif os(watchOS)
        return .result(dialog: "Switching to \(route.name).")
        #endif
    }
}

// MARK: - Route Destination

/// Where a newly imported or selected route should be delivered.
enum RouteDestinationEnum: String, AppEnum {
    /// Save to the phone app only (default import behaviour).
    case phoneOnly          = "phoneOnly"
    /// Save to the phone and transfer to the watch.
    case phoneAndWatch      = "phoneAndWatch"
    /// Save to the phone, transfer to the watch, and immediately start a ride.
    case phoneWatchStartRide = "phoneWatchStartRide"

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Destination")
    static var caseDisplayRepresentations: [RouteDestinationEnum: DisplayRepresentation] = [
        .phoneOnly:           "Phone Only",
        .phoneAndWatch:       "Phone & Watch",
        .phoneWatchStartRide: "Phone, Watch & Start Ride",
    ]
}

// MARK: - Send Route to Watch

/// Pushes an existing phone-side route to the watch, optionally starting a ride.
///
/// Intended uses:
/// - Shortcuts / Siri: "Send my Century Loop to the watch"
/// - Share sheet deep-link: receive a GPX, save it to phone, then call this
///   intent with the desired destination.
struct SendRouteToWatchIntent: AppIntent {
    static var title: LocalizedStringResource = "Send Route to Watch"
    static var description: IntentDescription = IntentDescription(
        "Sends a route from the phone to the Apple Watch, optionally starting a ride.",
        categoryName: "Route"
    )

    @Parameter(title: "Route", optionsProvider: RouteOptionsProvider())
    var route: RouteEntity

    @Parameter(title: "Destination", default: .phoneAndWatch)
    var destination: RouteDestinationEnum

    @Parameter(title: "Activity Type", default: .cycling)
    var activityType: ActivityTypeEnum

    func perform() async throws -> some IntentResult & ProvidesDialog {
        #if os(iOS)
        // .phoneOnly has nothing to do — the route is already on the phone.
        guard destination != .phoneOnly else {
            return .result(dialog: "\(route.name) is already on your phone.")
        }

        guard let fullRoute = await loadRoute(id: route.id) else {
            return .result(dialog: "Could not load route \"\(route.name)\".")
        }

        let action: String? = destination == .phoneWatchStartRide ? "startRide" : nil
        let activity = destination == .phoneWatchStartRide ? activityType.rawValue : nil
        
        await withCheckedContinuation { continuation in
            Task { @MainActor in
                ConnectivityManager.shared.sendRoute(
                    fullRoute,
                    pendingAction: action,
                    activityType: activity
                ) { result in
                    if case .failure(let error) = result {
                        print("[SendRouteToWatch] Transfer failed: \(error)")
                    }
                    continuation.resume()
                }
            }
        }

        switch destination {
        case .phoneAndWatch:
            return .result(dialog: "Sending \(route.name) to your watch.")
        case .phoneWatchStartRide:
            return .result(dialog: "Sending \(route.name) to your watch and starting a ride.")
        case .phoneOnly:
            return .result(dialog: "\(route.name) is already on your phone.")
        }
        #elseif os(watchOS)
        return .result(dialog: "Use the phone app to send routes to the watch.")
        #endif
    }

    struct RouteOptionsProvider: DynamicOptionsProvider {
        func results() async throws -> [RouteEntity] {
            try await RouteEntityQuery().suggestedEntities()
        }
    }
}

// MARK: - Helpers

/// Load the full Route model from disk by UUID (phone-side Documents/routes/).
private func loadRoute(id: UUID) -> Route? {
    let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
    let url  = docs
        .appendingPathComponent("routes", isDirectory: true)
        .appendingPathComponent("\(id.uuidString).json")
    guard let data = try? Data(contentsOf: url) else { return nil }
    return try? JSONDecoder().decode(Route.self, from: data)
}
