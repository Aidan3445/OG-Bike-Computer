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

    @Published var isRideActive = false {
        didSet {
            if oldValue && !isRideActive {
                if suppressAwaitingOnNextEnd {
                    suppressAwaitingOnNextEnd = false
                } else {
                    ConnectivityManager.shared.markAwaitingIncomingRide()
                }
            }
        }
    }
    @Published var isPaused = false

    /// Set when we're about to discard the ride — prevents the next true→false
    /// transition on `isRideActive` from showing a "Waiting for ride from watch"
    /// placeholder, since no ride will actually transfer.
    private var suppressAwaitingOnNextEnd = false

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

    /// Pending fallback resync task — cancelled when a real HK state callback arrives.
    private var pendingResyncTask: Task<Void, Never>?

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

    func holdRide() {
        ConnectivityManager.shared.sendHoldRide()
    }

    /// Send a discardRide command to the watch. Suppresses the "waiting for ride"
    /// placeholder since no ride will transfer.
    func sendDiscardRide() {
        suppressAwaitingOnNextEnd = true
        ConnectivityManager.shared.sendRideCommand(["type": "discardRide"])
    }

    // MARK: - Optimistic Updates

    /// Immediately flips `isPaused` to show feedback, issues the real pause command,
    /// then schedules a resync after 4 s as a fallback if the watch doesn't respond.
    func optimisticPause() {
        guard mirroredSession != nil else { return }
        DispatchQueue.main.async {
            self.isPaused = true
            self.writeStateToAppGroup()
        }
        pauseRide()
        scheduleResync()
    }

    /// Immediately flips `isPaused` to show feedback, issues the real resume command,
    /// then schedules a resync after 4 s as a fallback if the watch doesn't respond.
    func optimisticResume() {
        guard mirroredSession != nil else { return }
        DispatchQueue.main.async {
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        resumeRide()
        scheduleResync()
    }

    /// Immediately marks the ride as inactive, issues the real end command,
    /// then schedules a resync after 4 s as a fallback.
    func optimisticEnd() {
        guard mirroredSession != nil else { return }
        DispatchQueue.main.async {
            self.isRideActive = false
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        endRide()
        scheduleResync()
    }

    // MARK: - Resync

    /// Cancels any pending resync and schedules a new one 4 s from now.
    private func scheduleResync() {
        pendingResyncTask?.cancel()
        pendingResyncTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard !Task.isCancelled else { return }
            await MainActor.run { self?.syncFromSession() }
        }
    }

    /// Reconciles published state with the actual HK session state.
    /// Called by the fallback resync and can be called early when the real callback arrives.
    private func syncFromSession() {
        guard let state = mirroredSession?.state else {
            // Session gone — ride over
            isRideActive = false
            isPaused = false
            writeStateToAppGroup()
            return
        }
        switch state {
        case .running:
            isRideActive = true
            isPaused = false
        case .paused:
            isRideActive = true
            isPaused = true
        case .ended, .stopped:
            isRideActive = false
            isPaused = false
        default:
            break
        }
        writeStateToAppGroup()
    }

    // MARK: - State Updates

    /// Called by AppDelegate when the mirrored session state changes.
    func handleSessionStateChange(to state: HKWorkoutSessionState) {
        // Real confirmation arrived — cancel the fallback resync
        pendingResyncTask?.cancel()
        pendingResyncTask = nil
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

    /// Write the current moving time to App Group so the widget's EndRideIntent
    /// can decide whether to discard (short ride) or end normally.
    func writeMovingTimeToAppGroup(_ movingTime: TimeInterval) {
        appGroupDefaults?.set(movingTime, forKey: "movingTime")
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
        case "discard":
            // Short ride — discard both HK workout and app recording
            sendDiscardRide()
            RideNotificationManager.shared.postRideDiscarded()
        case "end":
            // Normal end — check moving time as a safety net
            let movingTime = PhoneTelemetryStore.shared.movingTime
            if movingTime < 60 {
                sendDiscardRide()
                RideNotificationManager.shared.postRideDiscarded()
            } else {
                endRide()
                RideNotificationManager.shared.postRideEnded()
            }
        case "hold":
            holdRide()
        default:
            break
        }
    }
}
#endif
