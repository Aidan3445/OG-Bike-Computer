//
//  ConnectivityManager+Session.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

/// Session lifecycle and routing for everything that arrives over WCSession.
/// Handlers live in the feature files.
extension ConnectivityManager: WCSessionDelegate {

    func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        DispatchQueue.main.async {
            self.activationState = activationState
            self.isReachable = session.isReachable

            #if os(iOS)
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
            self.requestWatchSync()
            #endif
        }

        if activationState == .activated, session.hasContentPending {
            print("WCSession has content pending delivery")
        }

        #if os(watchOS)
        if activationState == .activated {
            retryPendingTransfers()
            cleanupOldRides()
        }
        #endif
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isReachable = session.isReachable
        }

        #if os(watchOS)
        if session.isReachable {
            retryPendingTransfers()
            cleanupOldRides()
        }
        #endif
    }

    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) {
        DispatchQueue.main.async {
            self.isPaired = session.isPaired
            self.isWatchAppInstalled = session.isWatchAppInstalled
        }
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}
    func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif

    func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        DispatchQueue.main.async {
            self.applyWatchContext(applicationContext)
        }
    }

    // MARK: - Files

    func session(_ session: WCSession, didReceive file: WCSessionFile) {
        #if os(iOS)
        if file.metadata?["type"] as? String == "rideTrack" {
            handleRideTransfer(file)
        }
        #elseif os(watchOS)
        receiveRouteFile(file)
        #endif
    }

    func session(_ session: WCSession, didFinish fileTransfer: WCSessionFileTransfer, error: Error?) {
        #if os(iOS)
        cleanUpStagedRoute(fileTransfer, error: error)
        #elseif os(watchOS)
        finishRideTransfer(fileTransfer, error: error)
        #endif
    }

    // MARK: - User info

    func session(
        _ session: WCSession,
        didReceiveUserInfo userInfo: [String: Any] = [:]
    ) {
        DispatchQueue.main.async {
            self.lastEvent = "got userInfo: \(userInfo.keys)"
        }

        #if os(iOS)
        // Queued alerts can show up late. PhoneAlertReceiver drops expired ones.
        if let payload = AlertPayload.fromDict(userInfo) {
            DispatchQueue.main.async {
                self.onVoiceAlertReceived?(payload)
            }
            return
        }
        #endif

        if let data = userInfo["route"] as? Data,
           let route = try? JSONDecoder().decode(Route.self, from: data) {
            DispatchQueue.main.async {
                self.onRouteReceived?(route)
            }
        }

        guard let type = userInfo["type"] as? String else { return }

        switch type {
        case "metricConfig", "userSettings":
            receiveSettings(type: type, payload: userInfo)

        #if os(watchOS)
        case "rideAck":
            if let rideID = Self.rideID(in: userInfo) {
                handleTransferAck(rideID: rideID)
            }
        case "clearAllRoutes":
            clearAllRoutesFromPhone()
        case "holdRide":
            DispatchQueue.main.async { self.onHoldRideRequested?() }
        case "discardRide":
            DispatchQueue.main.async { self.onDiscardRideRequested?() }
        case "continueHeldRide":
            if let rideID = Self.rideID(in: userInfo) {
                receiveContinueHeldRide(rideID: rideID, payload: userInfo) { _ in }
            }
        case "deleteHeldRide":
            if let rideID = Self.rideID(in: userInfo) {
                deleteHeldRideFromPhone(rideID: rideID)
            }

        #elseif os(iOS)
        case "rideTerminalIntent":
            if let kind = userInfo["kind"] as? String {
                DispatchQueue.main.async { self.onWatchTerminalIntent?(kind) }
            }
        case "rideTransferStarting":
            if let rideID = Self.rideID(in: userInfo) {
                receiveRideTransferStarting(rideID: rideID, payload: userInfo)
            }
        case "deleteHeldRide":
            if let rideID = Self.rideID(in: userInfo) {
                deleteHeldRideFromWatch(rideID: rideID)
            }
        case "rideContinued":
            if let rideID = Self.rideID(in: userInfo) {
                DispatchQueue.main.async { self.dropContinuedHeldRide(rideID: rideID) }
            }
        #endif

        default:
            break
        }
    }

    // MARK: - Messages

    // Senders must pass a replyHandler, even an empty one. Messages sent
    // without one go to a delegate method we don't implement and are dropped.
    func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        if message["wake"] != nil {
            print("Woken by phone")
            replyHandler(["awake": true])
            return
        }

        #if os(iOS)
        // This reply only confirms delivery. The watch keeps its fallback
        // armed until the separate speech-started ack arrives.
        if let payload = AlertPayload.fromDict(message) {
            DispatchQueue.main.async {
                self.onVoiceAlertReceived?(payload)
            }
            replyHandler(["received": true, "id": payload.id.uuidString])
            return
        }
        #elseif os(watchOS)
        if let ack = AlertAck.fromDict(message) {
            DispatchQueue.main.async {
                self.onAlertAckReceived?(ack.id)
            }
            replyHandler(["received": true])
            return
        }
        if let finish = AlertFinish.fromDict(message) {
            DispatchQueue.main.async {
                self.onAlertFinishReceived?(finish.id)
            }
            replyHandler(["received": true])
            return
        }
        #endif

        guard let type = message["type"] as? String else {
            replyHandler([:])
            return
        }

        switch type {
        case "metricConfig", "userSettings":
            receiveSettings(type: type, payload: message)
            replyHandler(["received": true])

        #if os(watchOS)
        case "rideAck":
            if let rideID = Self.rideID(in: message) {
                handleTransferAck(rideID: rideID)
            }
            replyHandler(["received": true])
        case "clearAllRoutes":
            clearAllRoutesFromPhone()
            replyHandler(["cleared": true])
        case "startRide":
            receiveStartRide(message)
            replyHandler(["started": true])
        case "changeRoute":
            let routeID = (message["routeID"] as? String).flatMap { UUID(uuidString: $0) }
            DispatchQueue.main.async { self.onChangeRouteRequested?(routeID) }
            replyHandler(["changed": true])
        case "toggleVoice":
            DispatchQueue.main.async { self.onToggleVoiceRequested?() }
            replyHandler(["toggled": true])
        case "discardRide":
            DispatchQueue.main.async { self.onDiscardRideRequested?() }
            replyHandler(["discarded": true])
        case "holdRide":
            DispatchQueue.main.async { self.onHoldRideRequested?() }
            replyHandler(["held": true])
        case "sampleHaptic":
            let intensity = (message["intensity"] as? String) ?? "medium"
            DispatchQueue.main.async { self.onSampleHapticRequested?(intensity) }
            replyHandler(["played": true])
        case "continueHeldRide":
            guard let rideID = Self.rideID(in: message) else {
                replyHandler(["ok": false, "error": "Missing rideID"])
                return
            }
            receiveContinueHeldRide(rideID: rideID, payload: message) { error in
                if let error {
                    replyHandler(["ok": false, "error": error])
                } else {
                    replyHandler(["ok": true])
                }
            }
        case "deleteHeldRide":
            if let rideID = Self.rideID(in: message) {
                deleteHeldRideFromPhone(rideID: rideID)
            }
            replyHandler(["deleted": true])

        #elseif os(iOS)
        case "verifyRide":
            guard let rideID = Self.rideID(in: message) else {
                replyHandler([:])
                return
            }
            replyHandler(["present": rideIsOnDisk(rideID)])
        case "speech":
            guard let text = message["text"] as? String else {
                replyHandler([:])
                return
            }
            PhoneSpeechPlayer.shared.speak(text)
            replyHandler(["spoken": true])
        case "deleteHeldRide":
            guard let rideID = Self.rideID(in: message) else {
                replyHandler([:])
                return
            }
            deleteHeldRideFromWatch(rideID: rideID)
            replyHandler(["deleted": true])
        case "rideTerminalIntent":
            guard let kind = message["kind"] as? String else {
                replyHandler([:])
                return
            }
            DispatchQueue.main.async { self.onWatchTerminalIntent?(kind) }
            replyHandler(["received": true])
        case "rideContinued":
            guard let rideID = Self.rideID(in: message) else {
                replyHandler([:])
                return
            }
            DispatchQueue.main.async { self.dropContinuedHeldRide(rideID: rideID) }
            replyHandler(["received": true])
        #endif

        default:
            print("Unhandled message: \(message.keys), type \(type)")
            replyHandler([:])
        }
    }
}
#endif
