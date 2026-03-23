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

    private struct Entry: Codable {
        let rideID: UUID
        let transferDate: Date
        var confirmedDate: Date?

        var isConfirmed: Bool { confirmedDate != nil }
    }

    private var entries: [Entry] = []
    private let fileURL: URL

    private init() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        fileURL = docs.appendingPathComponent("transfer_ledger.json")
        load()
    }

    // MARK: - Public API

    /// Record a new ride transfer as pending.
    func recordTransfer(rideID: UUID) {
        guard !entries.contains(where: { $0.rideID == rideID }) else { return }
        entries.append(Entry(rideID: rideID, transferDate: Date(), confirmedDate: nil))
        save()
    }

    /// Mark a ride as confirmed received by the phone.
    func markConfirmed(rideID: UUID) {
        guard let idx = entries.firstIndex(where: { $0.rideID == rideID }) else { return }
        entries[idx].confirmedDate = Date()
        save()
    }

    /// Remove a ride from the ledger entirely (after cleanup).
    func remove(rideID: UUID) {
        entries.removeAll { $0.rideID == rideID }
        save()
    }

    /// Get IDs of rides that haven't been confirmed yet.
    func pendingRideIDs() -> [UUID] {
        entries.filter { !$0.isConfirmed }.map(\.rideID)
    }

    /// Get IDs of confirmed rides older than N days (ready for cleanup).
    func confirmedRideIDsOlderThan(days: Int) -> [UUID] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return entries
            .filter { $0.isConfirmed && ($0.confirmedDate ?? .distantFuture) < cutoff }
            .map(\.rideID)
    }

    /// Get IDs of unconfirmed rides older than N days (expired, phone probably never got them).
    func pendingRideIDsOlderThan(days: Int) -> [UUID] {
        let cutoff = Date().addingTimeInterval(-Double(days) * 86400)
        return entries
            .filter { !$0.isConfirmed && $0.transferDate < cutoff }
            .map(\.rideID)
    }

    /// Number of pending (unconfirmed) transfers.
    var pendingCount: Int {
        entries.filter { !$0.isConfirmed }.count
    }

    /// Total entries in the ledger.
    var totalCount: Int {
        entries.count
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
