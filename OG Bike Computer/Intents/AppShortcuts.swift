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
                "Start recording with \(.applicationName)",

                "Start a \(.applicationName) ride",
                "Begin a \(.applicationName) ride",
                "Start a \(.applicationName) free ride",
                "Start a \(.applicationName) recording",
                
                "Start \(.applicationName) ride",
                "Begin \(.applicationName) ride",
                "Start \(.applicationName) free ride",
                "Start \(.applicationName) recording",
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
                "Pause cycling in \(.applicationName)",

                "Pause my \(.applicationName) ride",
                "Pause \(.applicationName) ride",
                "Pause \(.applicationName) cycling",
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
                "Continue ride in \(.applicationName)",

                "Resume my \(.applicationName) ride",
                "Resume \(.applicationName) ride",
                "Continue \(.applicationName) ride",
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
                "Finish ride with \(.applicationName)",

                "End my \(.applicationName) ride",
                "Stop \(.applicationName) ride",
                "End \(.applicationName) cycling",
                "Finish \(.applicationName) ride",
                "End \(.applicationName) ride"
            ],
            shortTitle: "End Ride",
            systemImageName: "stop.fill"
        )

        // Change route
        AppShortcut(
            intent: ChangeRouteIntent(),
            phrases: [
                "Change route in \(.applicationName)",
                "Switch route in \(.applicationName)",

                "Change \(.applicationName) route",
                "Switch \(.applicationName) route",
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
                "Use \(\.$profile) settings in \(.applicationName)",

                "Switch \(.applicationName) to \(\.$profile) profile",
                "Select \(.applicationName) \(\.$profile) profile",
                "Use \(.applicationName) \(\.$profile) settings",
            ],
            shortTitle: "Select Profile",
            systemImageName: "gearshape.2"
        )

        // Select bike
        AppShortcut(
            intent: SelectBikeIntent(),
            phrases: [
                "Switch to \(\.$bike) in \(.applicationName)",
                "Select \(\.$bike) in \(.applicationName)",

                "Switch \(.applicationName) to \(\.$bike)",
                "Select \(.applicationName) \(\.$bike)",
            ],
            shortTitle: "Select Bike",
            systemImageName: "bicycle.circle"
        )
    }
}
