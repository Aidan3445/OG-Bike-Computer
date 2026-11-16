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
            if !oldValue && isRideActive {
                suppressAwaitingOnNextEnd = false
            } else if oldValue && !isRideActive {
                endedEarlyRideStart = mirroredSession == nil && earlySessionID != nil
                    ? PhoneTelemetryStore.shared.rideStartTime
                    : nil
                if let id = earlySessionID { endedEarlySessionID = id }
                earlySessionID = nil
                earlyWatchdog?.cancel()
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

    /// The watch's ID for the current ride's early telemetry, which shows
    /// the ride before HealthKit hands over the mirrored session.
    private var earlySessionID: String?
    /// Telemetry still in flight for this ride is ignored once it ends.
    private var endedEarlySessionID: String?
    /// Ends an early-only ride if its telemetry stops.
    private var earlyWatchdog: DispatchWorkItem?
    /// Start of the last ride that ended before HealthKit handed it over.
    private var endedEarlyRideStart: Date?

    /// Whether ride commands have a way to reach the watch.
    private var hasWatchLink: Bool {
        mirroredSession != nil || (isRideActive && earlySessionID != nil)
    }

    /// The mirrored workout session from the watch.
    /// Set by AppDelegate when mirroring starts; cleared when session ends.
    var mirroredSession: HKWorkoutSession? {
        didSet {
            let active = mirroredSession != nil
            DispatchQueue.main.async {
                if active, let id = self.earlySessionID {
                    // HealthKit has the ride now. Copies still in flight
                    // over WatchConnectivity are ignored.
                    self.earlyWatchdog?.cancel()
                    self.endedEarlySessionID = id
                    self.earlySessionID = nil
                }
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
        guard let session = mirroredSession else {
            sendEarlyCommand("pauseRide")
            return
        }
        guard session.state == .running else { return }
        session.pause()
    }

    func resumeRide() {
        guard let session = mirroredSession else {
            sendEarlyCommand("resumeRide")
            return
        }
        if session.state == .paused {
            session.resume()
            return
        }
        // While auto-paused the watch briefly runs the session to check for
        // movement, so there's no paused state to flip. Ask the watch directly.
        let payload = ["type": "resumeRide", "ts": String(Date().timeIntervalSince1970)]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        session.sendToRemoteWorkoutSession(data: data) { _, _ in }
    }

    func endRide() {
        guard let session = mirroredSession else {
            ConnectivityManager.shared.sendRideCommand(["type": "endRide"])
            return
        }
        session.end()
    }

    /// Pause or resume before HealthKit has handed over the session. The
    /// watch's reply stands in for the session state change.
    private func sendEarlyCommand(_ type: String) {
        ConnectivityManager.shared.sendRideCommand(["type": type]) { [weak self] in
            DispatchQueue.main.async { self?.clearPending() }
        }
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

    /// The watch is discarding the ride itself. Its message can land before
    /// or after the mirrored session ends, so this covers both.
    func watchWillDiscard() {
        if isRideActive {
            suppressAwaitingOnNextEnd = true
        }
        ConnectivityManager.shared.clearAwaitingIncomingRide()
    }

    // MARK: - Optimistic Updates

    /// Flips `isPaused = true` and shows a pending spinner immediately, then
    /// issues the real pause command. Spinner clears when the watch confirms
    /// via `handleSessionStateChange` or when the pending timeout fires.
    func optimisticPause() {
        guard hasWatchLink else { return }
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
        guard hasWatchLink else { return }
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
        beginTerminalCommand(.end, markStatus: { await $0.markCompleted() }) { [weak self] in
            self?.endRide()
        }
    }

    /// Like `optimisticEnd`, but issues Hold instead and flips the Live
    /// Activity to a "held" state.
    func optimisticHold() {
        beginTerminalCommand(.hold, markStatus: { await $0.markHeld() }) { [weak self] in
            self?.holdRide()
        }
    }

    /// Shared scaffold for the optimistic Hold / End flows:
    /// 1. mark pending command & flip `isRideActive` off (dismisses Ride tab)
    /// 2. await the live activity update so the terminal banner is actually
    ///    live before we proceed
    /// 3. wait `terminalRepaintDelay` so the rider sees it (rider is almost
    ///    always paused at this point, so the delay is invisible)
    /// 4. send the real watch command
    private func beginTerminalCommand(
        _ command: PendingCommand,
        markStatus: @escaping (LiveActivityManager) async -> Void,
        send: @escaping () -> Void
    ) {
        guard hasWatchLink else { return }
        beginPending(command)
        DispatchQueue.main.async {
            self.isRideActive = false
            self.isPaused = false
            self.writeStateToAppGroup()
        }
        Task {
            #if canImport(ActivityKit)
            await markStatus(LiveActivityManager.shared)
            try? await Task.sleep(
                nanoseconds: UInt64(LiveActivityManager.terminalRepaintDelay * 1_000_000_000)
            )
            #endif
            await MainActor.run { send() }
        }
    }

    /// Discard the ride with optimistic dismissal — flips the control screen
    /// off, stamps the Live Activity with a "Ride Discarded" (red) banner,
    /// and after `terminalRepaintDelay` sends the discard command. The delay
    /// matches Hold / End so the rider actually sees the banner before HK
    /// teardown clears the activity.
    func optimisticDiscard() {
        // Set the awaiting-placeholder suppression BEFORE beginTerminalCommand
        // flips `isRideActive = false`. The original synchronous path got
        // this for free because `sendDiscardRide()` (which sets the flag)
        // ran before the queued main-thread didSet fired. Now that `send()`
        // is deferred behind the 2.5s repaint delay, the didSet would
        // otherwise see `suppressAwaitingOnNextEnd == false` and show the
        // "Waiting for ride from watch" row, which is wrong for a discard.
        suppressAwaitingOnNextEnd = true
        beginTerminalCommand(.discard, markStatus: { await $0.markDiscarded() }) { [weak self] in
            self?.sendDiscardRide()
        }
    }

    // MARK: - Early Ride

    /// Telemetry that came straight from the watch. Shows the ride until
    /// HealthKit hands over the mirrored session. Returns false when the
    /// stats should be ignored: the ride ended, or HealthKit is already
    /// delivering them.
    func receiveEarlyTelemetry(sessionID: String) -> Bool {
        guard mirroredSession == nil, sessionID != endedEarlySessionID, !suppressActiveRevival else { return false }
        if earlySessionID != sessionID {
            earlySessionID = sessionID
            DiagnosticsLog.event("Mirroring", "early ride shown sessionID=\(sessionID)")
        }
        if !isRideActive {
            isRideActive = true
            writeStateToAppGroup()
        }
        armEarlyWatchdog()
        return true
    }

    /// HealthKit can still hand over a ride that ended during the wait.
    /// Matching its start to that ride keeps it from coming back.
    func isLateHandover(of session: HKWorkoutSession) -> Bool {
        guard let ended = endedEarlyRideStart, let start = session.startDate else { return false }
        return abs(start.timeIntervalSince(ended)) < 10
    }

    /// The watch ended a ride before HealthKit handed it over.
    func earlyRideEnded(sessionID: String) {
        guard sessionID == earlySessionID, mirroredSession == nil, isRideActive else { return }
        DiagnosticsLog.event("Mirroring", "early ride ended by watch sessionID=\(sessionID)")
        endEarlyRide()
    }

    private func armEarlyWatchdog() {
        earlyWatchdog?.cancel()
        let task = DispatchWorkItem { [weak self] in
            guard let self, self.mirroredSession == nil, self.isRideActive else { return }
            DiagnosticsLog.event("Mirroring", "early telemetry went quiet, ending ride")
            self.endEarlyRide()
        }
        earlyWatchdog = task
        // Three missed ticks at the slowest telemetry rate.
        DispatchQueue.main.asyncAfter(deadline: .now() + 15, execute: task)
    }

    private func endEarlyRide() {
        isRideActive = false
        isPaused = false
        writeStateToAppGroup()
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
                // The watch also runs the session while auto-paused to check
                // for movement. Telemetry says when the ride really resumed.
                if !PhoneTelemetryStore.shared.isAutoPaused {
                    self.isPaused = false
                }
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

    /// Follows the watch's own paused flag from telemetry. Session state alone
    /// reads as running during auto-pause movement checks, which flipped the
    /// phone and the Live Activity toggle to "Riding" mid auto-pause.
    func syncPaused(fromWatch watchPaused: Bool) {
        guard isRideActive, pendingCommand == nil, isPaused != watchPaused else { return }
        isPaused = watchPaused
        writeStateToAppGroup()
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
