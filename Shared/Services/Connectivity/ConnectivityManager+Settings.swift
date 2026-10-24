//
//  ConnectivityManager+Settings.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

extension ConnectivityManager {

    /// Handles a metricConfig or userSettings payload from either device.
    func receiveSettings(type: String, payload: [String: Any]) {
        guard let base64 = payload["data"] as? String,
              let data = Data(base64Encoded: base64) else { return }
        DispatchQueue.main.async {
            if type == "metricConfig" {
                self.onMetricConfigReceived?(data)
            } else {
                self.onUserSettingsReceived?(data)
            }
        }
    }
}

#if os(iOS)
extension ConnectivityManager {

    /// Sends right away when the watch is reachable, which also works mid ride.
    /// Otherwise it's queued.
    func sendMetricConfig(_ data: Data) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            let base64 = data.base64EncodedString()
            WCSession.default.sendMessage(
                ["type": "metricConfig", "data": base64],
                replyHandler: { _ in print("[MetricConfig] Sent via message") },
                errorHandler: { error in
                    print("[MetricConfig] Message failed, falling back to userInfo: \(error)")
                    WCSession.default.transferUserInfo(["type": "metricConfig", "data": base64])
                }
            )
        } else {
            let base64 = data.base64EncodedString()
            WCSession.default.transferUserInfo(["type": "metricConfig", "data": base64])
            print("[MetricConfig] Queued via userInfo")
        }
    }

    func sendUserSettings(_ data: Data) {
        guard WCSession.default.activationState == .activated else { return }

        if WCSession.default.isReachable {
            let base64 = data.base64EncodedString()
            WCSession.default.sendMessage(
                ["type": "userSettings", "data": base64],
                replyHandler: { _ in print("[UserSettings] Sent via message") },
                errorHandler: { error in
                    print("[UserSettings] Message failed, falling back to userInfo: \(error)")
                    WCSession.default.transferUserInfo(["type": "userSettings", "data": base64])
                }
            )
        } else {
            let base64 = data.base64EncodedString()
            WCSession.default.transferUserInfo(["type": "userSettings", "data": base64])
            print("[UserSettings] Queued via userInfo")
        }
    }

    /// Asks the watch to buzz at the intensity the rider just picked. Skipped
    /// when the watch isn't reachable. They'll feel it the next time they
    /// change the setting with the watch awake.
    func sendSampleHaptic(intensity: String) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else { return }
        WCSession.default.sendMessage(
            ["type": "sampleHaptic", "intensity": intensity],
            replyHandler: nil,
            errorHandler: nil
        )
    }
}
#endif
#endif
