//
//  TransferLedger.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/22/26.
//

import Foundation

/// Tracks ride transfer status on the watch.
/// Rides are kept locally until confirmed received by the phone,
/// then retained for a grace period before cleanup.
final class TransferLedger {
    static let shared = TransferLedger()

    enum Status {
        /// Ride has been confirmed received by the phone. Cleaned up `confirmedRetentionDays`
        /// days after confirmation.
        case confirmed(deletesAt: Date)
        /// Transfer is in flight or hasn't been acked yet. Cleaned up
        /// `pendingRetentionDays` days after the ride was first transferred.
        case pending(deletesAt: Date)
        /// Held ride was discarded by the user. Cleaned up `discardedRetentionDays`
        /// days after discard. The ride is still on disk so the user can undiscard.
        case discarded(deletesAt: Date)
        /// No ledger entry. Treat as not-yet-transferred — the watch will record one
        /// on the next sendRide call.
        case unknown
    }

    static let confirmedRetentionDays = 7
    static let pendingRetentionDays = 30
    static let discardedRetentionDays = 7

    private struct Entry: Codable {
        let rideID: UUID
        let transferDate: Date
        var confirmedDate: Date?
        var discardedDate: Date?

        var isConfirmed: Bool { confirmedDate != nil }
        var isDiscarded: Bool { discardedDate != nil }
    }

    private var entries: [Entry] = []
    private let fileURL: URL
    private let queue = DispatchQueue(label: "TransferLedger.queue")

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("transfer_ledger.json")
        queue.sync {
            load()
        }
    }

    // MARK: - Public API

    /// Record a new ride transfer as pending.
    func recordTransfer(rideID: UUID) {
        queue.sync {
            guard !entries.contains(where: { $0.rideID == rideID }) else { return }
            entries.append(Entry(rideID: rideID, transferDate: Date(), confirmedDate: nil))
            save()
        }
    }

    /// Mark a ride as confirmed received by the phone.
    func markConfirmed(rideID: UUID) {
        queue.sync {
            guard let idx = entries.firstIndex(where: { $0.rideID == rideID }) else { return }
            entries[idx].confirmedDate = Date()
            // Confirming undoes a prior discard — used when the user undiscards
            // and the phone eventually acks the transfer.
            entries[idx].discardedDate = nil
            save()
        }
    }

    /// Mark a ride as discarded by the user. Kept on disk for `discardedRetentionDays`
    /// so the user can undiscard.
    func markDiscarded(rideID: UUID) {
        queue.sync {
            if let idx = entries.firstIndex(where: { $0.rideID == rideID }) {
                entries[idx].discardedDate = Date()
            } else {
                // Held ride that never had a transfer recorded — record one now so the
                // entry exists for status lookups, then mark discarded.
                entries.append(Entry(
                    rideID: rideID,
                    transferDate: Date(),
                    confirmedDate: nil,
                    discardedDate: Date()
                ))
            }
            save()
        }
    }

    /// Clear the discarded flag for a ride (undiscard). Resets transferDate so the
    /// 30-day pending clock restarts from the undiscard moment.
    func markUndiscarded(rideID: UUID) {
        queue.sync {
            guard let idx = entries.firstIndex(where: { $0.rideID == rideID }) else { return }
            entries[idx].discardedDate = nil
            entries[idx].confirmedDate = nil
            entries[idx] = Entry(
                rideID: rideID,
                transferDate: Date(),
                confirmedDate: nil,
                discardedDate: nil
            )
            save()
        }
    }

    /// Status + remaining retention for a ride.
    func status(for rideID: UUID) -> Status {
        queue.sync {
            guard let entry = entries.first(where: { $0.rideID == rideID }) else {
                return .unknown
            }
            if let discardedDate = entry.discardedDate {
                let deletesAt = discardedDate.addingTimeInterval(
                    Double(Self.discardedRetentionDays) * 86400)
                return .discarded(deletesAt: deletesAt)
            }
            if let confirmedDate = entry.confirmedDate {
                let deletesAt = confirmedDate.addingTimeInterval(
                    Double(Self.confirmedRetentionDays) * 86400)
                return .confirmed(deletesAt: deletesAt)
            }
            let deletesAt = entry.transferDate.addingTimeInterval(
                Double(Self.pendingRetentionDays) * 86400)
            return .pending(deletesAt: deletesAt)
        }
    }

    /// Remove a ride from the ledger entirely (after cleanup).
    func remove(rideID: UUID) {
        queue.sync {
            entries.removeAll { $0.rideID == rideID }
            save()
        }
    }

    /// Get IDs of rides that haven't been confirmed yet (and aren't discarded —
    /// discarded rides don't auto-retry transfer).
    func pendingRideIDs() -> [UUID] {
        queue.sync {
            entries.filter { !$0.isConfirmed && !$0.isDiscarded }.map(\.rideID)
        }
    }

    /// Get IDs of discarded rides older than N days (ready for cleanup).
    func discardedRideIDsOlderThan(days: Int) -> [UUID] {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            return entries
                .filter { ($0.discardedDate ?? .distantFuture) < cutoff }
                .map(\.rideID)
        }
    }

    /// Get IDs of confirmed rides older than N days (ready for cleanup).
    func confirmedRideIDsOlderThan(days: Int) -> [UUID] {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            return entries
                .filter { $0.isConfirmed && ($0.confirmedDate ?? .distantFuture) < cutoff }
                .map(\.rideID)
        }
    }

    /// Get IDs of unconfirmed rides older than N days (expired, phone probably never got them).
    func pendingRideIDsOlderThan(days: Int) -> [UUID] {
        queue.sync {
            let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
            return entries
                .filter { !$0.isConfirmed && $0.transferDate < cutoff }
                .map(\.rideID)
        }
    }

    /// Number of pending (unconfirmed) transfers.
    var pendingCount: Int {
        queue.sync {
            entries.filter { !$0.isConfirmed }.count
        }
    }

    /// Total entries in the ledger.
    var totalCount: Int {
        queue.sync {
            entries.count
        }
    }

    // MARK: - Persistence

    private func save() {
        guard let data = try? JSONEncoder().encode(entries) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL),
              let decoded = try? JSONDecoder().decode([Entry].self, from: data) else { return }
        entries = decoded
    }
}
