//
//  RideSessionManager.swift
//  OG Bike Computer
//
//  Singleton that exposes the mirrored HK workout session for ride control
//  from App Intents, Live Activity buttons, and the Ride Control view.
//

#if os(iOS) && !WIDGET_EXTENSION
import Foundation
import HealthKit
import Combine

class RideSessionManager: ObservableObject {
    static let shared = RideSessionManager()

    @Published var isRideActive = false
    @Published var isPaused = false

    /// The mirrored workout session from the watch.
    /// Set by AppDelegate when mirroring starts; cleared when session ends.
    var mirroredSession: HKWorkoutSession? {
        didSet {
            let active = mirroredSession != nil
            DispatchQueue.main.async {
                self.isRideActive = active
                if !active { self.isPaused = false }
            }
            writeStateToAppGroup()
        }
    }

    private let appGroupDefaults = UserDefaults(suiteName: "group.com.aidan3445.computa")

    private init() {}

    // MARK: - Ride Control

    func pauseRide() {
        guard let session = mirroredSession,
              session.state == .running else { return }
        session.pause()
    }

    func resumeRide() {
        guard let session = mirroredSession,
              session.state == .paused else { return }
        session.resume()
    }

    func endRide() {
        guard let session = mirroredSession else { return }
        session.end()
    }

    // MARK: - State Updates

    /// Called by AppDelegate when the mirrored session state changes.
    func handleSessionStateChange(to state: HKWorkoutSessionState) {
        DispatchQueue.main.async {
            switch state {
            case .running:
                self.isRideActive = true
                self.isPaused = false
            case .paused:
                self.isRideActive = true
                self.isPaused = true
            case .ended, .stopped:
                self.isRideActive = false
                self.isPaused = false
                self.mirroredSession = nil
            default:
                break
            }
            self.writeStateToAppGroup()
        }
    }

    // MARK: - App Group Shared State

    /// Write ride state to App Group UserDefaults so the widget extension
    /// can read it (e.g. for LiveActivityIntent button state).
    private func writeStateToAppGroup() {
        appGroupDefaults?.set(isRideActive, forKey: "isRideActive")
        appGroupDefaults?.set(isPaused, forKey: "isPaused")
    }

    /// Read ride state from App Group (used by widget intents).
    static func readIsRideActive() -> Bool {
        UserDefaults(suiteName: "group.com.aidan3445.computa")?.bool(forKey: "isRideActive") ?? false
    }

    static func readIsPaused() -> Bool {
        UserDefaults(suiteName: "group.com.aidan3445.computa")?.bool(forKey: "isPaused") ?? false
    }

    // MARK: - Pending Widget Commands

    /// Check for and execute any pending command written by a LiveActivityIntent
    /// running in the widget extension process. Called periodically by the app
    /// (e.g. on each telemetry update).
    func processPendingWidgetCommand() {
        guard let command = appGroupDefaults?.string(forKey: "pendingRideCommand"),
              !command.isEmpty else { return }

        // Clear immediately to avoid double-processing
        appGroupDefaults?.removeObject(forKey: "pendingRideCommand")

        switch command {
        case "pause":
            pauseRide()
        case "resume":
            resumeRide()
        case "end":
            // Check moving time for discard logic
            let movingTime = PhoneTelemetryStore.shared.movingTime
            if movingTime < 60 {
                ConnectivityManager.shared.sendRideCommand(["type": "discardRide"])
            } else {
                endRide()
            }
        default:
            break
        }
    }
}
#endif
