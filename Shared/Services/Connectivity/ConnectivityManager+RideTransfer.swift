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
/// Transfers whose file the phone already saved, so a late "starting"
/// message stands out in the trace. Main thread only.
private var handledTransferIDs: Set<String> = []

extension ConnectivityManager {

    /// Shows the placeholder row for a ride the watch just ended. Clears itself
    /// after two minutes if no transfer shows up.
    func markAwaitingIncomingRide() {
        DispatchQueue.main.async { [self] in
            self.isAwaitingIncomingRide = true
            self.awaitingIncomingRideTimeout?.cancel()
            let task = DispatchWorkItem { [weak self] in
                self?.isAwaitingIncomingRide = false
            }
            self.awaitingIncomingRideTimeout = task
            // Wall clock so the timeout still fires if the phone slept.
            DispatchQueue.main.asyncAfter(wallDeadline: .now() + 120, execute: task)
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
        let transferID = payload["transferID"] as? String ?? "none"
        let onDisk = rideIsOnDisk(rideID)
        DispatchQueue.main.async {
            let alreadyHandled = handledTransferIDs.contains(transferID)
            DiagnosticsLog.event("Transfer", "starting received transferID=\(transferID) rideID=\(rideID) onDisk=\(onDisk) fileAlreadyHandled=\(alreadyHandled)")
            self.clearAwaitingIncomingRide()
            self.pendingTransferRideIDs.insert(rideID)
            DiagnosticsLog.event("Transfer", "pending insert rideID=\(rideID) count=\(self.pendingTransferRideIDs.count)")
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
        let transferID = file.metadata?["transferID"] as? String ?? "none"
        guard let summaryString = file.metadata?["summaryJSON"] as? String,
              let summaryData = summaryString.data(using: .utf8),
              var summary = try? JSONDecoder().decode(RideSummary.self, from: summaryData) else {
            DiagnosticsLog.event("Transfer", "file summary decode failed transferID=\(transferID)")
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
            DiagnosticsLog.event("Transfer", "file copy failed transferID=\(transferID) rideID=\(summary.id) error=\(error)")
            return
        }

        if let data = try? JSONEncoder().encode(summary) {
            try? data.write(to: summaryURL, options: .atomic)
        }

        DispatchQueue.main.async {
            if transferID != "none" {
                handledTransferIDs.insert(transferID)
            }
            self.pendingTransferRideIDs.remove(summary.id)
            DiagnosticsLog.event("Transfer", "pending remove rideID=\(summary.id) count=\(self.pendingTransferRideIDs.count)")
            self.clearAwaitingIncomingRide()
            if let store = self.rideStore {
                if let idx = store.rides.firstIndex(where: { $0.id == summary.id }) {
                    store.rides[idx] = summary
                } else {
                    store.rides.insert(summary, at: 0)
                }
            }
            DiagnosticsLog.event("Transfer", "file handled transferID=\(transferID) rideID=\(summary.id) onHold=\(summary.onHold) retransmit=\(isRetransmit) heldToCompleted=\(heldToCompleted)")

            // Plain retransmits of a finished ride are skipped so auto upload doesn't repeat.
            if !isRetransmit || heldToCompleted {
                self.onRideReceived?(summary)
            }
        }

        sendRideAck(rideID: summary.id, transferID: transferID)
    }

    func sendRideAck(rideID: UUID, transferID: String) {
        guard WCSession.default.activationState == .activated else {
            DiagnosticsLog.event("Transfer", "ack dropped, not activated transferID=\(transferID) rideID=\(rideID)")
            return
        }

        let msg: [String: Any] = ["type": "rideAck", "rideID": rideID.uuidString]

        if WCSession.default.isReachable {
            WCSession.default.sendMessage(msg, replyHandler: { _ in
                DiagnosticsLog.event("Transfer", "ack sent via message transferID=\(transferID) rideID=\(rideID)")
            }, errorHandler: { error in
                DiagnosticsLog.event("Transfer", "ack message failed, using userInfo transferID=\(transferID) rideID=\(rideID) error=\(error)")
                WCSession.default.transferUserInfo(msg)
            })
        } else {
            WCSession.default.transferUserInfo(msg)
            DiagnosticsLog.event("Transfer", "ack queued via userInfo transferID=\(transferID) rideID=\(rideID)")
        }
    }

    /// A summary file on disk is what puts a ride in the ride list.
    func rideIsOnDisk(_ rideID: UUID) -> Bool {
        let summaryURL = Self.ridesDirectory
            .appendingPathComponent("\(rideID.uuidString).json")
        return FileManager.default.fileExists(atPath: summaryURL.path)
    }

    // MARK: - Diagnostics

    /// Saves a diagnostics file from the watch. Copied right away since the
    /// system deletes it when the delegate returns.
    func receiveDiagnosticsFile(_ file: WCSessionFile) {
        guard DiagnosticsLog.isEnabled,
              let fileName = file.metadata?["fileName"] as? String else { return }
        let rideID = Self.rideID(in: file.metadata ?? [:])
        if DiagnosticsLog.storeWatchFile(file.fileURL, rideID: rideID, fileName: fileName) == nil {
            DiagnosticsLog.event("Diagnostics", "failed to save watch file \(fileName)")
        }
        DispatchQueue.main.async {
            NotificationCenter.default.post(name: .diagnosticsFilesChanged, object: nil)
        }
    }

    /// Asks the watch to send every diagnostics file it still has. The
    /// completion gets how many files it's sending.
    func requestWatchDiagnostics(completion: @escaping (Result<Int, Error>) -> Void) {
        guard WCSession.default.activationState == .activated,
              WCSession.default.isReachable else {
            completion(.failure(ConnectivityError.notReachable))
            return
        }
        WCSession.default.sendMessage(["type": "requestDiagnostics"], replyHandler: { reply in
            let count = reply["count"] as? Int ?? 0
            DispatchQueue.main.async { completion(.success(count)) }
        }, errorHandler: { error in
            DispatchQueue.main.async { completion(.failure(error)) }
        })
    }
}
#endif

#if os(watchOS)
extension ConnectivityManager {

    func sendRide(summary: RideSummary, trackURL: URL) {
        saveRideLocally(summary: summary, trackURL: trackURL)
        TransferLedger.shared.recordTransfer(rideID: summary.id)

        guard WCSession.default.activationState == .activated else {
            DiagnosticsLog.event("Transfer", "not activated, saved locally rideID=\(summary.id)")
            return
        }

        transferRideToPhone(summary: summary, reason: "initial")
        sendDiagnostics(rideID: summary.id)
    }

    /// Sends a ride whose track is already in the local rides directory.
    private func transferRideToPhone(summary: RideSummary, reason: String) {
        let trackURL = Self.ridesDirectory.appendingPathComponent(summary.trackFilename)
        guard FileManager.default.fileExists(atPath: trackURL.path) else {
            DiagnosticsLog.event("Transfer", "track file missing rideID=\(summary.id) reason=\(reason)")
            return
        }
        let transferID = UUID().uuidString

        DispatchQueue.main.async {
            self.inFlightTransferRideIDs.insert(summary.id)
        }

        // Lets the phone show the row before the file arrives.
        let summaryJSON = (try? JSONEncoder().encode(summary)).flatMap { String(data: $0, encoding: .utf8) } ?? ""
        WCSession.default.transferUserInfo([
            "type": "rideTransferStarting",
            "rideID": summary.id.uuidString,
            "transferID": transferID,
            "summaryJSON": summaryJSON
        ])

        WCSession.default.transferFile(
            trackURL,
            metadata: [
                "type": "rideTrack",
                "transferID": transferID,
                "summaryJSON": summaryJSON
            ]
        )

        DiagnosticsLog.event("Transfer", "queued transferID=\(transferID) rideID=\(summary.id) reason=\(reason) onHold=\(summary.onHold) outstanding=\(WCSession.default.outstandingFileTransfers.count)")
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
    func retryPendingTransfers(reason: String) {
        guard WCSession.default.activationState == .activated else { return }

        let pending = TransferLedger.shared.pendingRideIDs()
        guard !pending.isEmpty else { return }

        DiagnosticsLog.event("Transfer", "retrying \(pending.count) unconfirmed ride(s) reason=\(reason)")

        let dir = Self.ridesDirectory
        for rideID in pending {
            let summaryURL = dir.appendingPathComponent("\(rideID.uuidString).json")
            guard let data = try? Data(contentsOf: summaryURL),
                  let summary = try? JSONDecoder().decode(RideSummary.self, from: data) else {
                print("[Transfer] Cannot load summary for \(rideID), removing from ledger")
                TransferLedger.shared.remove(rideID: rideID)
                continue
            }
            transferRideToPhone(summary: summary, reason: reason)
        }
    }

    func handleTransferAck(rideID: UUID, via channel: String) {
        TransferLedger.shared.markConfirmed(rideID: rideID)
        DispatchQueue.main.async {
            self.inFlightTransferRideIDs.remove(rideID)
            // Views read the ledger through `transferStatus(for:)`, so nudge them to re-render.
            self.objectWillChange.send()
        }
        DiagnosticsLog.event("Transfer", "ack received via \(channel) rideID=\(rideID)")
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
        let transferID = meta?["transferID"] as? String ?? "none"
        DiagnosticsLog.event("Transfer", "file finished transferID=\(transferID) rideID=\(summary.id) error=\(error.map { "\($0)" } ?? "none")")
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
        transferRideToPhone(summary: summary, reason: "manual retry")
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
        transferRideToPhone(summary: summary, reason: "undiscard")
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

    // MARK: - Diagnostics

    /// Sends this ride's CSVs and the event log to the phone.
    func sendDiagnostics(rideID: UUID) {
        guard DiagnosticsLog.isEnabled else { return }
        DiagnosticsLog.queue.async {
            var files = DiagnosticsLog.rideFiles(rideID: rideID)
            let events = DiagnosticsLog.directory.appendingPathComponent(DiagnosticsLog.eventsFileName)
            if FileManager.default.fileExists(atPath: events.path) {
                files.append(events)
            }
            self.transferDiagnostics(files, rideID: rideID)
        }
    }

    /// Sends every diagnostics file still on the watch, for any ride. The
    /// completion gets how many.
    func sendAllDiagnostics(completion: @escaping (Int) -> Void) {
        guard DiagnosticsLog.isEnabled else {
            completion(0)
            return
        }
        DiagnosticsLog.queue.async {
            let files = DiagnosticsLog.allSendableFiles()
            self.transferDiagnostics(files, rideID: nil)
            completion(files.count)
        }
    }

    /// Transfers a snapshot of each file, since the live file may still be
    /// appended to. CSV names start with their ride ID.
    private func transferDiagnostics(_ files: [URL], rideID: UUID?) {
        DiagnosticsLog.event("Diagnostics", "sending \(files.count) file(s) rideID=\(rideID?.uuidString ?? "any")")
        DiagnosticsLog.pruneOutbox(olderThan: 7 * 24 * 3600)
        for url in files {
            let fileName = url.lastPathComponent
            let fileRideID = UUID(uuidString: String(fileName.prefix(36))) ?? rideID
            DiagnosticsLog.snapshot(url) { snapshot, size in
                guard let snapshot else { return }
                var metadata: [String: Any] = [
                    "type": "diagnostics",
                    "fileName": fileName,
                    "device": "watch",
                    "sourceSize": size
                ]
                if let fileRideID {
                    metadata["rideID"] = fileRideID.uuidString
                }
                WCSession.default.transferFile(snapshot, metadata: metadata)
            }
        }
    }

    /// Deletes the snapshot, and on success the source CSV too unless that
    /// ride is still on hold and may get more rows.
    func finishDiagnosticsTransfer(_ fileTransfer: WCSessionFileTransfer, error: Error?) {
        let meta = fileTransfer.file.metadata ?? [:]
        try? FileManager.default.removeItem(at: fileTransfer.file.fileURL)
        guard let fileName = meta["fileName"] as? String else { return }
        if let error {
            DiagnosticsLog.event("Diagnostics", "send failed \(fileName) error=\(error)")
            return
        }
        let size = (meta["sourceSize"] as? NSNumber)?.int64Value ?? -1
        let rideID = Self.rideID(in: meta)
        DispatchQueue.main.async {
            if let rideID, self.rideStore?.heldRide?.id == rideID { return }
            DiagnosticsLog.removeSentSource(fileName: fileName, snapshotSize: size)
        }
    }
}
#endif
#endif
