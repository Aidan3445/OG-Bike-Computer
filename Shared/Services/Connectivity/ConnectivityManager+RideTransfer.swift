//
//  ConnectivityManager+RideTransfer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

#if canImport(WatchConnectivity)
import Foundation
import WatchConnectivity
import Combine

// A finished or held ride is saved on the watch, sent to the phone as a track
// file with its summary in the metadata, and kept in TransferLedger as pending
// until the phone acks it.

#if os(iOS)
extension ConnectivityManager {

    /// Shows the placeholder row for a ride the watch just ended. Clears itself
    /// after two minutes if no transfer shows up.
    func markAwaitingIncomingRide() {
        DispatchQueue.main.async {
            self.isAwaitingIncomingRide = true
            self.awaitingIncomingRideTimeout?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.isAwaitingIncomingRide = false
            }
            self.awaitingIncomingRideTimeout = task
            DispatchQueue.main.asyncAfter(deadline: .now() + 120, execute: task)
        }
    }

    func clearAwaitingIncomingRide() {
        awaitingIncomingRideTimeout?.cancel()
        awaitingIncomingRideTimeout = nil
        if isAwaitingIncomingRide {
            isAwaitingIncomingRide = false
        }
    }

    /// The watch is about to send a ride. Adds its row right away with a spinner.
    func receiveRideTransferStarting(rideID: UUID, payload: [String: Any]) {
        DispatchQueue.main.async {
            self.clearAwaitingIncomingRide()
            self.pendingTransferRideIDs.insert(rideID)
            if let jsonStr = payload["summaryJSON"] as? String,
               let data = jsonStr.data(using: .utf8),
               let summary = try? JSONDecoder().decode(RideSummary.self, from: data) {
                if let store = self.rideStore,
                   !store.rides.contains(where: { $0.id == rideID }) {
                    store.rides.insert(summary, at: 0)
                }
            }
        }
    }

    /// Saves a ride file from the watch and acks it. The file is deleted when
    /// the delegate call returns, so it's copied right away.
    func handleRideTransfer(_ file: WCSessionFile) {
        guard let summaryString = file.metadata?["summaryJSON"] as? String,
              let summaryData = summaryString.data(using: .utf8),
              var summary = try? JSONDecoder().decode(RideSummary.self, from: summaryData) else {
            print("Failed to decode ride summary")
            return
        }

        let dir = Self.ridesDirectory
        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")

        // The watch never knows about uploads, so keep any the phone already recorded.
        let isRetransmit: Bool
        let existingWasHeld: Bool
        if let existingData = try? Data(contentsOf: summaryURL),
           let existingSummary = try? JSONDecoder().decode(RideSummary.self, from: existingData) {
            isRetransmit = true
            existingWasHeld = existingSummary.onHold
            if let existingUploads = existingSummary.uploads, !existingUploads.isEmpty {
                summary.uploads = existingUploads
            }
        } else {
            isRetransmit = false
            existingWasHeld = false
        }

        // A held ride coming back without the hold flag was just finished, so
        // it counts as a new ride for auto upload.
        let heldToCompleted = isRetransmit && existingWasHeld && !summary.onHold

        let destURL = dir.appendingPathComponent(summary.trackFilename)
        do {
            if FileManager.default.fileExists(atPath: destURL.path) {
                try FileManager.default.removeItem(at: destURL)
            }
            try FileManager.default.copyItem(at: file.fileURL, to: destURL)
        } catch {
            print("Failed to copy track file: \(error)")
            return
        }

        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL, options: .atomic)
        }

        DispatchQueue.main.async {
            self.pendingTransferRideIDs.remove(summary.id)
            self.clearAwaitingIncomingRide()
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
            print("Ride received: \(summary.name)\(isRetransmit ? " (retransmit)" : "")\(heldToCompleted ? " [finalized]" : "")")

            // Plain retransmits of a finished ride are skipped so auto upload doesn't repeat.
            if !isRetransmit || heldToCompleted {
                self.onRideReceived?(summary)
            }
        }

        sendRideAck(rideID: summary.id)
    }

    func sendRideAck(rideID: UUID) {
        guard WCSession.default.activationState == .activated else { return }

        let msg: [String: Any] = ["type": "rideAck", "rideID": rideID.uuidString]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in
                print("[Transfer] Ack sent via message for \(rideID)")
            }, errorHandler: { error in
                print("[Transfer] Ack message failed, using userInfo: \(error)")
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            print("[Transfer] Ack queued via userInfo for \(rideID)")
        }
    }

    /// A summary file on disk is what puts a ride in the ride list.
    func rideIsOnDisk(_ rideID: UUID) -> Bool {
        let summaryURL = Self.ridesDirectory
            .appendingPathComponent("\(rideID.uuidString).json")
        return FileManager.default.fileExists(atPath: summaryURL.path)
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    func sendRide(summary: RideSummary, trackURL: URL) {
        saveRideLocally(summary: summary, trackURL: trackURL)
        TransferLedger.shared.recordTransfer(rideID: summary.id)

        guard WCSession.default.activationState == .activated else {
            print("Cannot send ride: WCSession not activated (saved locally, will retry)")
            return
        }

        transferRideToPhone(summary: summary)
    }

    /// Sends a ride whose track is already in the local rides directory.
    private func transferRideToPhone(summary: RideSummary) {
        let trackURL = Self.ridesDirectory.appendingPathComponent(summary.trackFilename)
        guard FileManager.default.fileExists(atPath: trackURL.path) else {
            print("[Transfer] Track file missing for \(summary.name), cannot transfer")
            return
        }

        DispatchQueue.main.async {
            self.inFlightTransferRideIDs.insert(summary.id)
        }

        // Lets the phone show the row before the file arrives.
        let summaryJSON = (try? JSONEncoder().encode(summary)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        WCSession.default.transferUserInfo([
            "type": "rideTransferStarting",
            "rideID": summary.id.uuidString,
            "summaryJSON": summaryJSON
        ])

        WCSession.default.transferFile(
            trackURL,
            metadata: [
                "type": "rideTrack",
                "summaryJSON": summaryJSON
            ]
        )

        print("Queued ride transfer: \(summary.name)")
    }

    private func saveRideLocally(summary: RideSummary, trackURL: URL) {
        let dir = Self.ridesDirectory

        // Always overwrite so repeated holds keep the latest track. Finalizing a
        // held ride passes the local copy itself, and removing it before copying
        // onto itself would delete the track.
        let destTrack = dir.appendingPathComponent(summary.trackFilename)
        if trackURL.standardizedFileURL != destTrack.standardizedFileURL {
            try? FileManager.default.removeItem(at: destTrack)
            try? FileManager.default.copyItem(at: trackURL, to: destTrack)
        }

        let summaryURL = dir.appendingPathComponent("\(summary.id.uuidString).json")
        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL)
        }

        DispatchQueue.main.async {
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
        }

        print("Ride saved locally on watch: \(summary.name)")
    }

    /// Resends every ride the phone hasn't acked yet.
    func retryPendingTransfers() {
        guard WCSession.default.activationState == .activated else { return }

        let pending = TransferLedger.shared.pendingRideIDs()
        guard !pending.isEmpty else { return }

        print("[Transfer] Retrying \(pending.count) unconfirmed ride(s)")

        let dir = Self.ridesDirectory
        for rideID in pending {
            let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
            guard let data = try? Data(contentsOf: summaryURL),
                  let summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
                print("[Transfer] Cannot load summary for \(rideID), removing from ledger")
                TransferLedger.shared.remove(rideID: rideID)
                continue
            }
            transferRideToPhone(summary: summary)
        }
    }

    func handleTransferAck(rideID: UUID) {
        TransferLedger.shared.markConfirmed(rideID: rideID)
        DispatchQueue.main.async {
            self.inFlightTransferRideIDs.remove(rideID)
            // Views read the ledger through `transferStatus(for:)`, so nudge them to re-render.
            self.objectWillChange.send()
        }
        print("[Transfer] Confirmed: \(rideID)")
    }

    /// Clears the in-flight spinner once the bytes have left the watch. This
    /// doesn't confirm the ride. Only the phone's ack does that, since the
    /// phone can still fail to read the file.
    func finishRideTransfer(_ fileTransfer: WCSessionFileTransfer, error: Error?) {
        let meta = fileTransfer.file.metadata
        guard meta?["type"] as? String == "rideTrack",
              let summaryJSON = meta?["summaryJSON"] as? String,
              let data = summaryJSON.data(using: .utf8),
              let summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
            return
        }
        if let error = error {
            print("[Transfer] didFinish error for \(summary.id): \(error)")
        }
        DispatchQueue.main.async {
            self.inFlightTransferRideIDs.remove(summary.id)
        }
    }

    /// Asks the phone whether an acked ride is still in its ride list. Only
    /// worth calling for rides the ledger marks confirmed. Results are cached,
    /// so pass `force` after a retry.
    func verifyPhonePresence(rideID: UUID, force: Bool = false) {
        if !force {
            switch phonePresenceByRide[rideID] {
            case .checking, .present, .missing:
                return
            case .unknown, .none:
                break
            }
        }
        // Leave it unknown when unreachable so the row shows plain "transferred"
        // and checks again next time it appears.
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            return
        }
        DispatchQueue.main.async {
            self.phonePresenceByRide[rideID] = .checking
        }
        let msg: [String: Any] = ["type": "verifyRide", "rideID": rideID.uuidString]
        WCSession.default.sendMessage(msg, replyHandler: { [weak self] reply in
            let present = (reply["present"] as? Bool) ?? false
            DispatchQueue.main.async {
                self?.phonePresenceByRide[rideID] = present ? .present : .missing
            }
        }, errorHandler: { [weak self] error in
            print("[Verify] sendMessage failed for \(rideID): \(error)")
            DispatchQueue.main.async {
                self?.phonePresenceByRide[rideID] = .unknown
            }
        })
    }

    /// Resends a ride from the watch's ride history.
    func retryTransfer(rideID: UUID) {
        let dir = Self.ridesDirectory
        let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
        guard let data = try? Data(contentsOf: summaryURL),
              let summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
            print("[Transfer] retryTransfer: cannot load summary for \(rideID)")
            return
        }
        guard WCSession.default.activationState == .activated else {
            print("[Transfer] retryTransfer: WCSession not activated")
            return
        }
        // Back to pending until the phone acks again. This also restarts the
        // 30 day retention clock.
        TransferLedger.shared.markUndiscarded(rideID: rideID)
        DispatchQueue.main.async {
            self.phonePresenceByRide[rideID] = .unknown
        }
        transferRideToPhone(summary: summary)
    }

    /// Restores a discarded ride and sends it to the phone.
    func undiscardRide(rideID: UUID) {
        let dir = Self.ridesDirectory
        let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
        guard let data = try? Data(contentsOf: summaryURL),
              var summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
            print("[Transfer] undiscardRide: cannot load summary for \(rideID)")
            return
        }
        summary.wasDiscarded = nil
        if let json = try? JSONEncoder().encode(summary) {
            try? json.write(to: summaryURL, options: .atomic)
        }
        DispatchQueue.main.async {
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == rideID }) {
                    store.rides[idx] = summary
                }
            }
        }
        TransferLedger.shared.markUndiscarded(rideID: rideID)
        guard WCSession.default.activationState == .activated else {
            print("[Transfer] undiscardRide: WCSession not activated, will retry on activation")
            return
        }
        transferRideToPhone(summary: summary)
    }

    /// Deletes confirmed and discarded rides after 7 days, and unconfirmed
    /// rides after 30 since they're probably not coming back.
    func cleanupOldRides() {
        let dir = Self.ridesDirectory
        let fm = FileManager.default

        let confirmedToRemove = TransferLedger.shared.confirmedRideIDsOlderThan(
            days: TransferLedger.confirmedRetentionDays)
        for rideID in confirmedToRemove {
            deleteLocalRide(rideID: rideID, dir: dir, fm: fm)
            TransferLedger.shared.remove(rideID: rideID)
            print("[Transfer] Cleaned up confirmed ride: \(rideID)")
        }

        let expiredToRemove = TransferLedger.shared.pendingRideIDsOlderThan(
            days: TransferLedger.pendingRetentionDays)
        for rideID in expiredToRemove {
            deleteLocalRide(rideID: rideID, dir: dir, fm: fm)
            TransferLedger.shared.remove(rideID: rideID)
            print("[Transfer] Expired unconfirmed ride: \(rideID)")
        }

        let discardedToRemove = TransferLedger.shared.discardedRideIDsOlderThan(
            days: TransferLedger.discardedRetentionDays)
        for rideID in discardedToRemove {
            deleteLocalRide(rideID: rideID, dir: dir, fm: fm)
            TransferLedger.shared.remove(rideID: rideID)
            print("[Transfer] Cleaned up discarded ride: \(rideID)")
        }
    }
}
#endif
#endif
