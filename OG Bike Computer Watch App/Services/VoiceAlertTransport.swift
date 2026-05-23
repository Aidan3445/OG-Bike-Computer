//
//  VoiceAlertTransport.swift
//  OG Bike Computer Watch App
//
//  Watch-side router for voice alerts. The plan's core fix: instead of
//  "send to phone, hope it speaks, fall back on timeout" with no real
//  defense against silent failure, this races a phone send against a
//  bounded fallback timer (see plan §3.4).
//
//  For .immediate alerts:
//    1. Send via WCSession.sendMessage AND arm an 800ms FallbackTimer in
//       parallel.
//    2. Phone acks on AVSpeechSynthesizer.didStart (not didFinish) → that
//       cancels the timer.
//    3. Timer fires first → speak locally on the watch.
//
//  For .soon alerts (split readouts, halfway, queued non-urgent):
//    Use transferUserInfo. Guaranteed eventual delivery, no fallback —
//    these are best-effort phone delivery; if phone is unreachable they
//    just don't get spoken on the watch.
//
//  Per-ride force-disable:
//    If isCompanionAppInstalled is false at ride start, or
//    startMirroringToCompanionDevice failed, set `phonePathDisabled = true`
//    for the whole ride. All alerts → watch local.

import Foundation
import WatchConnectivity
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "VoiceAlertTransport")

final class VoiceAlertTransport {
    static let shared = VoiceAlertTransport()

    /// Whether the phone path is usable for this ride. Set to false when
    /// companion app isn't installed, mirroring failed at start, or other
    /// terminal conditions. Resets on each `start()`.
    private var phonePathDisabled = false

    /// Final outcome reported back to the caller exactly once per
    /// `deliver(_:completion:)` call.
    enum Outcome {
        /// Phone confirmed AVSpeechSynthesizer.didStart for this alert.
        /// Caller should treat the alert as "phone is speaking it" and
        /// advance any local queue accordingly.
        case phoneSpoke(latency: TimeInterval)
        /// Phone path didn't work (no reachability / send error / ack
        /// timeout). Caller should speak `text` locally on the watch.
        case localFallback(text: String, reason: String)
    }

    /// In-flight bookkeeping. Each entry is an alert we've sent to the
    /// phone, waiting for either ack or fallback. Keyed by alert id.
    private struct InFlight {
        let payload: AlertPayload
        let fallbackTimer: DispatchWorkItem
        let completion: (Outcome) -> Void
        let sentAt: Date
    }
    private var inFlight: [UUID: InFlight] = [:]

    /// Fallback deadline for .immediate alerts. Plan §3.4 suggests 0.5–1.0s,
    /// but real-world telemetry shows watch→didStart latency landing around
    /// 800–1100ms with WCSession.sendMessage during a mirrored workout.
    /// 1.5s gives comfortable headroom above the observed P95 without
    /// blowing past the rider's perception window for "this turn alert is
    /// late." Adjust based on telemetry of real ack latencies.
    private static let immediateFallbackSeconds: TimeInterval = 1.5

    private init() {}

    // MARK: Lifecycle

    /// Call when a ride starts. Resets per-ride state and arms the ack
    /// listener on ConnectivityManager.
    func start() {
        cancelAllInFlight(reason: "ride starting")
        phonePathDisabled = false

        // Probe right now so we log the starting state for telemetry.
        let session = WCSessionSnapshot.now()
        if !session.isCompanionAppInstalled {
            phonePathDisabled = true
            logger.warning("[Transport] Phone path DISABLED for ride: companion app not installed")
        } else {
            logger.notice("[Transport] start — reachable=\(session.isReachable) activation=\(session.activationStateRaw)")
        }

        // Wire the ack callback. Singleton listener; assignment replaces
        // any previous one (which would have been from a prior ride).
        ConnectivityManager.shared.onAlertAckReceived = { [weak self] id in
            self?.handleAck(id: id)
        }
    }

    /// Call when a ride ends or is held. Cancels any pending fallbacks so
    /// they don't fire after the synthesizer/audio session has been torn
    /// down.
    func stop() {
        cancelAllInFlight(reason: "ride ending")
        ConnectivityManager.shared.onAlertAckReceived = nil
    }

    /// Force the phone path off for the remainder of this ride. Called by
    /// WorkoutManager if mirroring breaks irrecoverably mid-ride. Doesn't
    /// cancel in-flight alerts — their fallback timers handle that.
    func disablePhonePath(reason: String) {
        guard !phonePathDisabled else { return }
        phonePathDisabled = true
        logger.warning("[Transport] Phone path DISABLED mid-ride: \(reason)")
    }

    // MARK: Public delivery

    /// Deliver an alert. `completion` is called exactly once with the
    /// resolved outcome — either the phone acked didStart (`.phoneSpoke`)
    /// or the phone path failed and the caller should speak locally
    /// (`.localFallback`). The transport never speaks locally itself —
    /// the caller owns the watch TTS path.
    func deliver(_ payload: AlertPayload, completion: @escaping (Outcome) -> Void) {
        switch payload.priority {
        case .immediate:
            deliverImmediate(payload, completion: completion)
        case .soon:
            deliverSoon(payload, completion: completion)
        case .background:
            // Not used for speech today. Surface as fallback so the alert
            // doesn't disappear.
            completion(.localFallback(text: payload.text, reason: "backgroundPriority"))
        }
    }

    // MARK: Immediate path

    private func deliverImmediate(_ payload: AlertPayload, completion: @escaping (Outcome) -> Void) {
        let logID = payload.id.uuidString.prefix(8)

        // Per-ride force-disable bypasses every other check.
        guard !phonePathDisabled else {
            logger.notice("[Transport] id=\(logID) → watchLocal (phone path disabled)")
            recordOutcome(payload, outcome: "watchLocal-disabled", latency: 0)
            completion(.localFallback(text: payload.text, reason: "phonePathDisabled"))
            return
        }

        let snapshot = WCSessionSnapshot.now()
        logger.notice("[Transport] deliver id=\(logID) kind=\(payload.kind.rawValue) reachable=\(snapshot.isReachable) installed=\(snapshot.isCompanionAppInstalled)")

        // Arm the fallback timer FIRST so it's running regardless of how
        // sendImmediateAlert returns. The timer's only job is "fire local
        // if no ack within the deadline."
        let timer = DispatchWorkItem { [weak self] in
            self?.handleFallback(id: payload.id, reason: "timeout")
        }
        let context = InFlight(
            payload: payload,
            fallbackTimer: timer,
            completion: completion,
            sentAt: Date()
        )
        inFlight[payload.id] = context
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.immediateFallbackSeconds, execute: timer)

        // Send. Note: the replyHandler completion is NOT the speech ack —
        // it just confirms the phone received the message. The watch still
        // waits for `onAlertAckReceived` (didStart from PhoneSpeechPlayer)
        // to cancel the fallback. This is the critical anti-double-speak
        // detail from plan §3.5.
        ConnectivityManager.shared.sendImmediateAlert(payload) { [weak self] success, error in
            guard let self else { return }
            if !success {
                // Send failed synchronously — no point waiting for an ack
                // that won't come. Fire the fallback now.
                let reason = error.map { "\($0)" } ?? "no reachability"
                logger.warning("[Transport] id=\(logID) send failed: \(reason) — firing fallback now")
                self.handleFallback(id: payload.id, reason: "sendFailed:\(reason)")
            } else {
                logger.info("[Transport] id=\(logID) sendMessage replyHandler returned (received). Waiting for didStart ack…")
            }
        }
    }

    // MARK: Soon path

    private func deliverSoon(_ payload: AlertPayload, completion: @escaping (Outcome) -> Void) {
        let logID = payload.id.uuidString.prefix(8)

        guard !phonePathDisabled else {
            logger.notice("[Transport] id=\(logID) (.soon) → watchLocal (phone path disabled)")
            completion(.localFallback(text: payload.text, reason: "phonePathDisabled"))
            return
        }

        // transferUserInfo doesn't require reachability — it queues and
        // delivers when possible. The receiver enforces expiry. The watch
        // doesn't wait for ack on these because they're not time-sensitive.
        ConnectivityManager.shared.sendQueuedAlert(payload)
        logger.notice("[Transport] id=\(logID) (.soon) queued via transferUserInfo")
        recordOutcome(payload, outcome: "queuedForPhone", latency: 0)
        // From the caller's perspective this is "phone is handling it" —
        // return a synthetic phoneSpoke so the watch's local queue advances
        // and we don't double-speak on the watch.
        completion(.phoneSpoke(latency: 0))
    }

    // MARK: Ack / fallback handling

    private func handleAck(id: UUID) {
        guard let context = inFlight.removeValue(forKey: id) else {
            // Late ack (after fallback already fired) or duplicate. Logged
            // for telemetry but otherwise ignored. Don't double-speak.
            logger.info("[Transport] ack id=\(id.uuidString.prefix(8)) — no matching in-flight (late or duplicate)")
            return
        }
        context.fallbackTimer.cancel()
        let latency = Date().timeIntervalSince(context.sentAt)
        logger.notice("[Transport] ACK id=\(id.uuidString.prefix(8)) — phone speaking (latency=\(String(format: "%.0f", latency * 1000))ms)")
        recordOutcome(context.payload, outcome: "phoneSpoke", latency: latency)
        context.completion(.phoneSpoke(latency: latency))
    }

    private func handleFallback(id: UUID, reason: String) {
        guard let context = inFlight.removeValue(forKey: id) else {
            // Already acked, or already fallback-fired. No-op.
            return
        }
        context.fallbackTimer.cancel()
        let latency = Date().timeIntervalSince(context.sentAt)
        logger.warning("[Transport] FALLBACK id=\(id.uuidString.prefix(8)) reason=\(reason) elapsed=\(String(format: "%.0f", latency * 1000))ms — speaking on watch")
        recordOutcome(context.payload, outcome: "watchSpoke-\(reason)", latency: latency)
        context.completion(.localFallback(text: context.payload.text, reason: reason))
    }

    private func cancelAllInFlight(reason: String) {
        for (_, context) in inFlight {
            context.fallbackTimer.cancel()
        }
        if !inFlight.isEmpty {
            logger.notice("[Transport] cancelled \(self.inFlight.count) in-flight (\(reason))")
        }
        inFlight.removeAll()
    }

    // MARK: Telemetry

    /// One line per delivered alert, structured for easy log grep. Captures
    /// the data needed to answer "are we hitting >90%?" — outcome +
    /// latency per id is what tells us whether the new architecture works.
    private func recordOutcome(_ payload: AlertPayload, outcome: String, latency: TimeInterval) {
        logger.notice("[AlertOutcome] id=\(payload.id.uuidString.prefix(8)) kind=\(payload.kind.rawValue) priority=\(payload.priority.rawValue) outcome=\(outcome) latency_ms=\(String(format: "%.0f", latency * 1000))")
    }
}

// MARK: - WCSession snapshot

/// Captures WCSession state at a single point in time. Pulling these into
/// a struct avoids races where we check `isReachable` and `isCompanionApp-
/// Installed` separately and get inconsistent reads.
private struct WCSessionSnapshot {
    let isReachable: Bool
    let isCompanionAppInstalled: Bool
    let activationStateRaw: Int

    static func now() -> WCSessionSnapshot {
        let s = WCSession.default
        return WCSessionSnapshot(
            isReachable: s.isReachable,
            isCompanionAppInstalled: s.isCompanionAppInstalled,
            activationStateRaw: s.activationState.rawValue
        )
    }
}
