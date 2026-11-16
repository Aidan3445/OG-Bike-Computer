//
//  ConnectivityManager+RideCommands.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

#if os(iOS)
extension ConnectivityManager {

    /// Sends a ride command like startRide, changeRoute or toggleVoice.
    /// Queued if the watch isn't reachable. `onReply` runs only when the
    /// watch replies directly.
    func sendRideCommand(_ message: [String: Any], onReply: (() -> Void)? = nil) {
        let type = message["type"] as? String ?? "?"
        guard WCSession.default.activationState == .activated else {
            DiagnosticsLog.event("Command", "\(type) dropped, session not activated")
            return
        }

        if WCSession.default.isReachable {
            let sent = Date()
            WCSession.default.sendMessage(message, replyHandler: { reply in
                let wait = String(format: "%.1f", Date().timeIntervalSince(sent))
                DiagnosticsLog.event("Command", "\(type) replied after=\(wait)s reply=\(reply)")
                onReply?()
            }, errorHandler: { error in
                let wait = String(format: "%.1f", Date().timeIntervalSince(sent))
                DiagnosticsLog.event("Command", "\(type) failed after=\(wait)s error=\(error.localizedDescription), queued via userInfo")
                WCSession.default.transferUserInfo(message)
            })
        } else {
            WCSession.default.transferUserInfo(message)
            DiagnosticsLog.event("Command", "\(type) watch not reachable, queued via userInfo")
        }
    }

    /// Tells the watch it can stop sending early telemetry. Not queued,
    /// since the watch stops on its own soon after anyway.
    func sendMirrorAttached() {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(["type": "mirrorAttached"], replyHandler: { _ in }, errorHandler: { _ in })
    }

    func sendHoldRide() {
        sendRideCommand(["type": "holdRide"])
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    func receiveStartRide(_ message: [String: Any]) {
        let routeID = (message["routeID"] as? String).flatMap { UUID(uuidString: $0) }
        let activityStr = message["activity"] as? String ?? "cycling"
        let activity = ActivityType(rawValue: activityStr) ?? .cycling
        DispatchQueue.main.async {
            self.onStartRideRequested?(routeID, activity)
        }
    }

    /// Telemetry sent straight to the phone while it waits on HealthKit for
    /// the mirrored session. Dropped if the phone isn't reachable, since the
    /// next tick replaces it.
    func sendEarlyTelemetry(_ payload: [String: String]) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(payload, replyHandler: { _ in }, errorHandler: { _ in })
    }

    /// The ride ended before the phone got the mirrored session, so it
    /// won't see the session end. If this is lost, the phone gives up after
    /// telemetry stops.
    func sendEarlyRideEnded(sessionID: String) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        let msg: [String: Any] = ["type": "earlyRideEnded", "sessionID": sessionID]
        WCSession.default.sendMessage(msg, replyHandler: { _ in }, errorHandler: { _ in })
    }

    /// Tells the phone the ride is about to end as "held" or "discarded" so
    /// the Live Activity shows the right banner. Sent as a message so it
    /// usually beats the workout session ending. If the phone is unreachable
    /// it's queued, and the banner catches up when the ride file arrives.
    func sendRideTerminalIntent(_ kind: String) {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "rideTerminalIntent", "kind": kind]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }
}
#endif
#endif
