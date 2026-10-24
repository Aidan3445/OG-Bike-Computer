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
    /// Queued if the watch isn't reachable.
    func sendRideCommand(_ message: [String: Any]) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(message, replyHandler: { reply in
                print("[RideCommand] Sent: \(message["type"] ?? "?"), reply: \(reply)")
            }, errorHandler: { error in
                print("[RideCommand] Failed: \(error). Queuing via userInfo.")
                WCSession.default.transferUserInfo(message)
            })
        } else {
            WCSession.default.transferUserInfo(message)
            print("[RideCommand] Watch not reachable, queued via userInfo")
        }
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
