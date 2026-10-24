//
//  ConnectivityManager+HeldRides.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity

#if os(iOS)
extension ConnectivityManager {

    /// Asks the watch to resume a held ride. The summary goes along in case
    /// the watch lost its copy. The completion reflects the watch's reply,
    /// so callers should show failures instead of assuming it worked.
    func sendContinueHeldRide(
        summary: RideSummary,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        guard WCSession.default.activationState == .activated else {
            completion(.failure(ConnectivityError.notReachable))
            return
        }

        let summaryJSON = (try? JSONEncoder().encode(summary))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        let msg: [String: Any] = [
            "type": "continueHeldRide",
            "rideID": summary.id.uuidString,
            "summaryJSON": summaryJSON
        ]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { [weak self] reply in
                if let ok = reply["ok"] as? Bool, ok {
                    // Drop the held copy now rather than waiting for rideContinued,
                    // so End & Save can't run against a ride that's recording again.
                    DispatchQueue.main.async {
                        self?.dropContinuedHeldRide(rideID: summary.id)
                    }
                    completion(.success(()))
                } else {
                    let reason = (reply["error"] as? String)
                        ?? "Watch could not continue the held ride."
                    completion(.failure(ConnectivityError.watchOperationFailed(reason)))
                }
            }, errorHandler: { error in
                WCSession.default.transferUserInfo(msg)
                completion(.failure(error))
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            completion(.failure(ConnectivityError.notReachable))
        }
    }

    /// Marks the phone's copy of a held ride complete, then tells the watch
    /// to delete its copy.
    func sendFinalizeHeldRide(summary: RideSummary, rideStore: RideStore) {
        var completed = summary
        completed.isOnHold = nil
        completed.wasAutoFinalized = nil
        rideStore.update(completed)

        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": summary.id.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Deletes a held ride here and on the watch. This sends deleteHeldRide
    /// rather than discardRide because the watch deletes by id, while
    /// discardRide depends on the watch's held ride already being loaded,
    /// which isn't guaranteed when the message wakes it.
    func sendDiscardRide(rideID: UUID) {
        deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
        DispatchQueue.main.async {
            if let store = self.rideStore,
               let ride = store.rides.first(where: { $0.id == rideID }) {
                store.delete(ride)
            }
        }
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": rideID.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: nil, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Removes the phone's copy of a held ride that's recording again on the
    /// watch. A fresh summary arrives with the next hold or end.
    func dropContinuedHeldRide(rideID: UUID) {
        deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
        DispatchQueue.main.async { [weak self] in
            guard let store = self?.rideStore,
                  let ride = store.rides.first(where: { $0.id == rideID }) else { return }
            store.delete(ride)
        }
    }

    /// The watch discarded a held ride.
    func deleteHeldRideFromWatch(rideID: UUID) {
        deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
        DispatchQueue.main.async {
            if let store = self.rideStore,
               let ride = store.rides.first(where: { $0.id == rideID }) {
                store.delete(ride)
            }
        }
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    /// Hands a continue request to the app. `reply` gets nil on success or an error message.
    func receiveContinueHeldRide(
        rideID: UUID,
        payload: [String: Any],
        reply: @escaping (String?) -> Void
    ) {
        let providedSummary: RideSummary? = {
            guard let json = payload["summaryJSON"] as? String,
                  let data = json.data(using: .utf8) else { return nil }
            return try? JSONDecoder().decode(RideSummary.self, from: data)
        }()
        DispatchQueue.main.async {
            guard let handler = self.onContinueHeldRideRequested else {
                reply("Watch handler not registered")
                return
            }
            handler(rideID, providedSummary, reply)
        }
    }

    /// The phone finalized or discarded a held ride.
    func deleteHeldRideFromPhone(rideID: UUID) {
        deleteLocalRide(rideID: rideID, dir: Self.ridesDirectory, fm: FileManager.default)
        DispatchQueue.main.async {
            if let store = self.rideStore,
               let ride = store.rides.first(where: { $0.id == rideID }) {
                store.delete(ride)
            }
            TransferLedger.shared.remove(rideID: rideID)
        }
    }

    /// Tells the phone a held ride was discarded on the watch.
    func sendDiscardRide(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "deleteHeldRide", "rideID": rideID.uuidString]
        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in }, errorHandler: { _ in
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
        }
    }

    /// Tells the phone a held ride is recording again so it drops its "On Hold"
    /// row. The updated summary arrives with the next hold or end.
    func sendRideContinued(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }
        let msg: [String: Any] = ["type": "rideContinued", "rideID": rideID.uuidString]
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
