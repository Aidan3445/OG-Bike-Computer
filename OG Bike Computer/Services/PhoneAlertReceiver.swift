//
//  PhoneAlertReceiver.swift
//  OG Bike Computer
//
//  Phone-side receiver for watch-originated voice alerts.
//  Owns: dedupe cache, expiry check, hand-off to PhoneSpeechPlayer, ack
//  back to the watch on didStart.
//
//  Wired up at app launch (see AppDelegate.didFinishLaunchingWithOptions).
//  Sits on the ConnectivityManager.onVoiceAlertReceived callback so it sees
//  alerts arriving via both sendMessage (.immediate) and transferUserInfo
//  (.soon) without caring about which path they came from.
//

#if !WIDGET_EXTENSION && os(iOS)
import Foundation
import os
import AVFoundation
import HealthKit

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "PhoneAlertReceiver")

final class PhoneAlertReceiver: @unchecked Sendable {
    static let shared = PhoneAlertReceiver()

    /// LRU dedupe cache. WCSession can occasionally redeliver — and a
    /// transferUserInfo arriving after a sendMessage of the same alert id
    /// (e.g. the watch retried) must not double-speak.
    private var seenIDs: [UUID] = []
    private let dedupeCapacity = 64

    private init() {}

    /// Install the receiver on ConnectivityManager. Idempotent — safe to
    /// call multiple times (e.g. on app re-foreground).
    func install() {
        ConnectivityManager.shared.onVoiceAlertReceived = { [weak self] payload in
            self?.handle(payload)
        }
        logger.notice("[AlertRecv] Installed on ConnectivityManager")
    }

    func handle(_ payload: AlertPayload) {
        let logID = payload.id.uuidString.prefix(8)
        let age = Date().timeIntervalSince(payload.createdAt)
        logger.notice("[AlertRecv] received id=\(logID) kind=\(payload.kind.rawValue) priority=\(payload.priority.rawValue) age=\(String(format: "%.2f", age))s text=\"\(payload.text)\"")

        // Drop expired — transferUserInfo can deliver these well after they
        // were relevant. The watch's fallback already spoke locally.
        if Date() > payload.expiresAt {
            logger.info("[AlertRecv] DROP id=\(logID) — expired (age=\(String(format: "%.1f", age))s)")
            return
        }

        // Dedupe — WCSession occasionally redelivers and the watch may
        // send the same id via both paths in pathological cases.
        if seenIDs.contains(payload.id) {
            logger.info("[AlertRecv] DROP id=\(logID) — already seen")
            return
        }
        markSeen(payload.id)

        // Hand to the speech player. The onStart callback fires when
        // AVSpeechSynthesizer reports the utterance has actually begun —
        // that's when we ack back so the watch cancels its FallbackTimer.
        // onFinish fires when the utterance completes; the watch uses it to
        // release the next line of a paced readout (splits).
        PhoneSpeechPlayer.shared.speak(
            payload.text,
            id: payload.id,
            onStart: { [weak self] startedID in
                self?.sendAck(id: startedID, originalCreatedAt: payload.createdAt)
            },
            onFinish: { [weak self] finishedID in
                self?.sendFinish(id: finishedID)
            }
        )

        // Side-effect: post a turn notification if user has that mode on.
        // Matches the existing behavior of the legacy HK mirror path.
        postNotificationIfNeeded(payload)
    }

    private func markSeen(_ id: UUID) {
        seenIDs.append(id)
        if seenIDs.count > dedupeCapacity {
            seenIDs.removeFirst(seenIDs.count - dedupeCapacity)
        }
    }

    private func sendAck(id: UUID, originalCreatedAt: Date) {
        let logID = id.uuidString.prefix(8)
        let totalLatency = Date().timeIntervalSince(originalCreatedAt)
        logger.notice("[AlertRecv] ACK id=\(logID) (watch→didStart=\(String(format: "%.2f", totalLatency))s)")

        // Send the ack via the HK workout mirror channel rather than
        // WCSession.sendMessage. Real-world telemetry shows phone→watch
        // sendMessage hitting WCErrorCodeDeliveryFailed during rides even
        // when the watch is clearly alive (mirrored workout active). The
        // HK mirror channel is bidirectional and known to be up for the
        // duration of the workout, so it's the right transport for this
        // ack. The watch decodes "alertAck" in didReceiveDataFromRemote-
        // WorkoutSession and dispatches via the same onAlertAckReceived
        // hook VoiceAlertTransport already listens on.
        guard let session = RideSessionManager.shared.mirroredSession else {
            // No mirrored session — ride ended between speak and didStart,
            // or the session was never set up. Fall back to WCSession;
            // best-effort.
            logger.warning("[AlertRecv] No mirroredSession for ack id=\(logID), falling back to WCSession")
            ConnectivityManager.shared.sendAlertAck(id: id)
            return
        }
        sendMirrorSignal(session: session, type: "alertAck", id: id, logLabel: "ack")
    }

    /// Phone finished speaking `id`. Same transport rules as the didStart
    /// ack: HK mirror channel first, WCSession best-effort fallback. If it's
    /// lost, the watch's pacing timeout advances the queue on its own.
    private func sendFinish(id: UUID) {
        let logID = id.uuidString.prefix(8)
        logger.notice("[AlertRecv] FINISH id=\(logID)")
        guard let session = RideSessionManager.shared.mirroredSession else {
            ConnectivityManager.shared.sendAlertFinish(id: id)
            return
        }
        sendMirrorSignal(session: session, type: "alertFinish", id: id, logLabel: "finish")
    }

    private func sendMirrorSignal(session: HKWorkoutSession, type: String, id: UUID, logLabel: String) {
        let logID = id.uuidString.prefix(8)
        let payload: [String: String] = [
            "type": type,
            "id": id.uuidString,
            "ts": String(Date().timeIntervalSince1970)
        ]
        guard let data = try? JSONEncoder().encode(payload) else { return }
        session.sendToRemoteWorkoutSession(data: data) { success, error in
            if let error {
                logger.error("[AlertRecv] HK mirror \(logLabel) send error id=\(logID): \(error.localizedDescription)")
            } else if !success {
                logger.error("[AlertRecv] HK mirror \(logLabel) reported failure id=\(logID)")
            }
        }
    }

    /// Post a system notification for turn alerts when the user has
    /// `showTurnNotifications` enabled. Live Activity is always on; this
    /// is the user's opt-in for additional banner notifications on each
    /// navigation event.
    private func postNotificationIfNeeded(_ payload: AlertPayload) {
        guard let data = UserDefaults.standard.data(forKey: "phoneAlerts"),
              let phonePrefs = try? JSONDecoder().decode(PhoneAlertPreferences.self, from: data),
              phonePrefs.showTurnNotifications else { return }
        switch payload.kind {
        case .offRoute:
            TurnNotificationManager.shared.postOffRoute(message: payload.text)
        case .turnApproach, .turnImmediate, .backOnRoute:
            TurnNotificationManager.shared.post(text: payload.text)
        default:
            // splits/halfway/arrival aren't navigation-turn notifications.
            break
        }
    }
}
#endif // !WIDGET_EXTENSION && os(iOS)
