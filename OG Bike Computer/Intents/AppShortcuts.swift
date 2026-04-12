//
//  AppShortcuts.swift
//  OG Bike Computer
//
//  Provides preconfigured App Shortcuts for Siri, Spotlight, Shortcuts app,
//  and the iPhone Action Button.
//

import AppIntents

struct AppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        // Start a ride (with optional route)
        AppShortcut(
            intent: StartRideIntent(),
            phrases: [
                "Start a ride with \(.applicationName)",
                "Start cycling with \(.applicationName)",
                "Begin a ride in \(.applicationName)",
                "Start a free ride with \(.applicationName)",
                "Start recording with \(.applicationName)"
            ],
            shortTitle: "Start Ride",
            systemImageName: "bicycle"
        )

        // Pause
        AppShortcut(
            intent: PauseRideAppIntent(),
            phrases: [
                "Pause my ride in \(.applicationName)",
                "Pause ride with \(.applicationName)",
                "Pause cycling in \(.applicationName)"
            ],
            shortTitle: "Pause Ride",
            systemImageName: "pause.fill"
        )

        // Resume
        AppShortcut(
            intent: ResumeRideAppIntent(),
            phrases: [
                "Resume my ride in \(.applicationName)",
                "Resume ride with \(.applicationName)",
                "Continue ride in \(.applicationName)"
            ],
            shortTitle: "Resume Ride",
            systemImageName: "play.fill"
        )

        // End ride
        AppShortcut(
            intent: EndRideAppIntent(),
            phrases: [
                "End my ride in \(.applicationName)",
                "Stop ride with \(.applicationName)",
                "End cycling in \(.applicationName)",
                "Finish ride with \(.applicationName)"
            ],
            shortTitle: "End Ride",
            systemImageName: "stop.fill"
        )

        // Change route
        AppShortcut(
            intent: ChangeRouteIntent(),
            phrases: [
                "Change route in \(.applicationName)",
                "Switch route in \(.applicationName)"
            ],
            shortTitle: "Change Route",
            systemImageName: "arrow.triangle.swap"
        )

        // Select settings profile
        AppShortcut(
            intent: SelectSettingsProfileIntent(),
            phrases: [
                "Switch to \(\.$profile) profile in \(.applicationName)",
                "Select \(\.$profile) profile in \(.applicationName)",
                "Use \(\.$profile) settings in \(.applicationName)"
            ],
            shortTitle: "Select Profile",
            systemImageName: "gearshape.2"
        )

        // Select bike
        AppShortcut(
            intent: SelectBikeIntent(),
            phrases: [
                "Switch to \(\.$bike) in \(.applicationName)",
                "Select \(\.$bike) in \(.applicationName)"
            ],
            shortTitle: "Select Bike",
            systemImageName: "bicycle.circle"
        )
    }
}
