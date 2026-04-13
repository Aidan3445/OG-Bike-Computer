//
//  WatchAppShortcuts.swift
//  OG Bike Computer Watch App
//
//  Watch-side AppShortcutsProvider that registers WatchStartWorkoutIntent
//  (StartWorkoutIntent protocol) for Siri and Shortcuts discovery.
//  This gives the system foreground/HealthKit guarantees that generic
//  AppIntent lacks — critical for starting workouts from background.
//

#if os(watchOS)
import AppIntents

struct WatchAppShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: WatchStartWorkoutIntent(),
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

        AppShortcut(
            intent: WatchPauseWorkoutIntent(),
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

        AppShortcut(
            intent: WatchResumeWorkoutIntent(),
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
    }
}
#endif
