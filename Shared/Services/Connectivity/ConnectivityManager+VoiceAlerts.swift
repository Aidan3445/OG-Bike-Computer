//
//  ConnectivityManager+VoiceAlerts.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

#if os(iOS)
extension ConnectivityManager {

    /// Tells the watch the phone started speaking `id` so it can cancel its
    /// fallback. If this is lost the watch speaks too, which beats silence.
    func sendAlertAck(id: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        guard WCSession.default.isReachable else {
            // The watch doesn't handle queued acks, and its fallback will have fired by now anyway.
            WCSession.default.transferUserInfo(AlertAck(id: id).toDict())
            return
        }
        WCSession.default.sendMessage(
            AlertAck(id: id).toDict(),
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }

    /// Tells the watch the phone finished speaking `id`. Used when the mirrored
    /// workout channel is gone. If it never lands, the watch's pacing timeout
    /// moves the queue along.
    func sendAlertFinish(id: UUID) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            AlertFinish(id: id).toDict(),
            replyHandler: { _ in },
            errorHandler: { _ in }
        )
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    /// For alerts that have to play within a second. Calls back with false
    /// when the phone can't be reached so the caller can speak locally.
    /// A true result only means the phone got the message. Wait for
    /// `onAlertAckReceived` to know it actually started speaking.
    func sendImmediateAlert(_ payload: AlertPayload, completion: @escaping (Bool, Error?) -> Void) {
        guard WCSession.default.activationState == .activated else {
            completion(false, ConnectivityError.notActivated)
            return
        }
        guard WCSession.default.isCompanionAppInstalled else {
            completion(false, ConnectivityError.companionAppNotInstalled)
            return
        }
        guard WCSession.default.isReachable else {
            completion(false, ConnectivityError.notReachable)
            return
        }
        WCSession.default.sendMessage(
            payload.toDict(),
            replyHandler: { _ in completion(true, nil) },
            errorHandler: { error in completion(false, error) }
        )
    }

    /// For alerts that can arrive late, like split announcements and stat
    /// readouts. Delivery is guaranteed and the phone drops anything past
    /// its `expiresAt`.
    func sendQueuedAlert(_ payload: AlertPayload) {
        guard WCSession.default.activationState == .activated else { return }
        WCSession.default.transferUserInfo(payload.toDict())
    }
}
#endif
#endif
