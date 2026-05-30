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

    /// A user-initiated ride command awaiting confirmation from the watch.
    /// Drives spinner/disabled state on the control buttons.
    enum PendingCommand: Equatable {
        case pause, resume, hold, end, discard
    }

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
    @Published var pendingCommand: PendingCommand?

    /// Set when we're about to discard the ride — prevents the next true→false
    /// transition on `isRideActive` from showing a "Waiting for ride from watch"
    /// placeholder, since no ride will actually transfer.
    private var suppressAwaitingOnNextEnd = false

    /// True while an optimistic terminal command (end/hold/discard) is in flight.
    /// Blocks `mirroredSession.didSet` from re-enabling `isRideActive` until the
    /// watch confirms by clearing the session.
    private var suppressActiveRevival = false

    /// The mirrored workout session from the watch.
    /// Set by AppDelegate when mirroring starts; cleared when session ends.
    var mirroredSession: HKWorkoutSession? {
        didSet {
            let active = mirroredSession != nil
            DispatchQueue.main.async {
                if active && self.suppressActiveRevival {
                    // User has already optimistically ended/held/discarded —
                    // don't bounce the UI back to active just because the
                    // mirrored session is still around.
                    return
                }
                self.isRideActive = active
                if !active { self.isPaused = false }
            }
            writeStateToAppGroup()
        }
    }

    private let appGroupDefaults = UserDefaults(suiteName: "group.com.aidan3445.computa")

    /// Clears `pendingCommand` and the optimistic revival lock if the watch
    /// never confirms. Does NOT revert optimistic state — the user's intent
    /// stands until a real HK callback says otherwise.
    private var pendingTimeoutTask: Task<Void, Never>?

    /// How long the UI shows a pending spinner before giving up on the watch.
    /// Past this, the spinner clears but optimistic state remains.
    private let pendingTimeout: TimeInterval = 6.0

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

    /// Flips `isPaused = true` and shows a pending spinner immediately, then
    /// issues the real pause command. Spinner clears when the watch confirms
    /// via `handleSessionStateChange` or when the pending timeout fires.
    func optimisticPause() {
        guard mirroredSession != nil else { return }
        beginPending(.pause)
        DispatchQueue.main.async {
            self.isPaused = true
            self.writeStateToAppGroup()
        }
        pauseRide()
    }

    /// Flips `isPaused = false` and shows a pending spinner immediately, then
    /// issues the real resume command.
    func optimisticResume() {
        guard mirroredSession != nil else { return }
        beginPending(.resume)
        DispatchQueue.main.async {
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        resumeRide()
    }

    /// Marks the ride inactive (dismissing the control screen), flips the Live
    /// Activity to "completed", and after a short beat issues End. Suppresses
    /// any mirrored-session republish from bouncing the UI back to active.
    func optimisticEnd() {
        beginTerminalCommand(.end, markStatus: { $0.markCompleted() }) { [weak self] in
            self?.endRide()
        }
    }

    /// Like `optimisticEnd`, but issues Hold instead and flips the Live
    /// Activity to a "held" state.
    func optimisticHold() {
        beginTerminalCommand(.hold, markStatus: { $0.markHeld() }) { [weak self] in
            self?.holdRide()
        }
    }

    /// Shared scaffold for the optimistic Hold / End flows:
    /// 1. mark pending command & flip `isRideActive` off (dismisses Ride tab)
    /// 2. stamp the live activity with a terminal status so the user sees it
    /// 3. wait `terminalRepaintDelay` so the activity actually paints
    /// 4. send the real watch command
    private func beginTerminalCommand(
        _ command: PendingCommand,
        markStatus: (LiveActivityManager) -> Void,
        send: @escaping () -> Void
    ) {
        guard mirroredSession != nil else { return }
        beginPending(command)
        DispatchQueue.main.async {
            self.isRideActive = false
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        #if canImport(ActivityKit)
        markStatus(LiveActivityManager.shared)
        let delay = LiveActivityManager.terminalRepaintDelay
        #else
        let delay: TimeInterval = 0
        #endif
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: send)
    }

    /// Discard the ride with optimistic dismissal — flips the control screen
    /// off and sends the discard command in the background.
    func optimisticDiscard() {
        guard mirroredSession != nil else { return }
        beginPending(.discard)
        DispatchQueue.main.async {
            self.isRideActive = false
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        #if canImport(ActivityKit)
        LiveActivityManager.shared.markCompleted()
        #endif
        sendDiscardRide()
    }

    // MARK: - Pending Command Tracking

    /// Mark a command in-flight. Sets `pendingCommand`, locks active-revival
    /// for terminal commands, and starts a timeout that clears the spinner
    /// (but not the optimistic state) if the watch never confirms.
    private func beginPending(_ command: PendingCommand) {
        pendingTimeoutTask?.cancel()
        let isTerminal = command == .end || command == .hold || command == .discard
        if isTerminal {
            suppressActiveRevival = true
        }
        DispatchQueue.main.async {
            self.pendingCommand = command
        }
        let timeout = pendingTimeout
        pendingTimeoutTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard !Task.isCancelled else { return }
            await MainActor.run {
                self?.pendingCommand = nil
                self?.suppressActiveRevival = false
            }
        }
    }

    /// Clear pending state — called when the watch confirms via a real HK
    /// state change.
    private func clearPending() {
        pendingTimeoutTask?.cancel()
        pendingTimeoutTask = nil
        suppressActiveRevival = false
        DispatchQueue.main.async {
            self.pendingCommand = nil
        }
    }

    // MARK: - State Updates

    /// Called by AppDelegate when the mirrored session state changes —
    /// authoritative confirmation from the watch.
    func handleSessionStateChange(to state: HKWorkoutSessionState) {
        clearPending()
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
            optimisticPause()
        case "resume":
            optimisticResume()
        case "discard":
            // Short ride — discard both HK workout and app recording
            optimisticDiscard()
            RideNotificationManager.shared.postRideDiscarded()
        case "end":
            // Normal end — check moving time as a safety net
            let movingTime = PhoneTelemetryStore.shared.movingTime
            if movingTime < 60 {
                optimisticDiscard()
                RideNotificationManager.shared.postRideDiscarded()
            } else {
                optimisticEnd()
                RideNotificationManager.shared.postRideEnded()
            }
        case "hold":
            optimisticHold()
        default:
            break
        }
    }
}
#endif
