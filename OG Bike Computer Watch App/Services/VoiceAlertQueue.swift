//
//  VoiceAlertQueue.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 4/25/26.
//

import Foundation

enum AlertPriority: Int, Comparable {
    case stat           = 10   // split/halfway individual utterances
    case navEvent       = 20   // off-route, back-on-route, arrival, last-turn-complete
    case autoPause      = 30   // auto-pause / auto-resume
    case turnApproach   = 40   // secondary and primary approach alerts
    case immediateTurn  = 50   // at-turn — always fires next, no exceptions

    static func < (lhs: AlertPriority, rhs: AlertPriority) -> Bool {
        lhs.rawValue < rhs.rawValue
    }
}

struct VoiceAlert {
    let id: UUID
    let priority: AlertPriority
    let text: String
    let mode: AlertMode
    let category: String?

    // Inter-alert interaction keys
    let alertKey: String?         // this alert's own identity
    let mutualCancelKey: String?  // if a queued alert has alertKey == mutualCancelKey, both are removed
    let replacesKey: String?      // if a queued alert has alertKey == replacesKey, remove it (self wins)

    /// Called at dequeue time. Returning false silently drops the alert
    /// instead of speaking it — used to suppress stale turn-approach,
    /// off-route, or back-on-route alerts that no longer reflect reality
    /// by the time the queue gets around to them.
    let relevanceCheck: (() -> Bool)?

    /// Plays even with voice turned off, for alerts the rider asked for by hand.
    let ignoresVoiceToggle: Bool

    init(
        priority: AlertPriority,
        text: String,
        mode: AlertMode = .voiceAndHaptic,
        category: String? = nil,
        alertKey: String? = nil,
        mutualCancelKey: String? = nil,
        replacesKey: String? = nil,
        relevanceCheck: (() -> Bool)? = nil,
        ignoresVoiceToggle: Bool = false
    ) {
        self.id = UUID()
        self.priority = priority
        self.text = text
        self.mode = mode
        self.category = category
        self.alertKey = alertKey
        self.mutualCancelKey = mutualCancelKey
        self.replacesKey = replacesKey
        self.relevanceCheck = relevanceCheck
        self.ignoresVoiceToggle = ignoresVoiceToggle
    }

    /// Short tag for `events.log` lines, so one alert can be followed from queue to speech.
    var logLabel: String {
        "\(id.uuidString.prefix(8)) \(category ?? "-") key=\(alertKey ?? "-") p=\(priority)"
    }
}

final class VoiceAlertQueue {
    private var storage: [VoiceAlert] = []

    var isEmpty: Bool { storage.isEmpty }
    var count: Int { storage.count }

    /// Enqueue with mutual-cancel and replacement logic applied first.
    /// Returns false if the alert was mutually cancelled (neither alert plays).
    @discardableResult
    func enqueue(_ alert: VoiceAlert) -> Bool {
        // Mutual cancel: if a queued alert shares the mutual cancel key, both are removed
        if let cancelKey = alert.mutualCancelKey,
           let idx = storage.firstIndex(where: { $0.alertKey == cancelKey }) {
            let cancelled = storage.remove(at: idx)
            DiagnosticsLog.event("Voice", "mutual cancel \(alert.logLabel) with queued \(cancelled.logLabel), neither plays, queue=\(storage.count)")
            return false
        }
        // Replacement: remove any queued alert this one supersedes
        if let replacesKey = alert.replacesKey {
            remove(reason: "superseded by \(alert.logLabel)") { $0.alertKey == replacesKey }
        }
        storage.append(alert)
        DiagnosticsLog.event("Voice", "enqueued \(alert.logLabel) queue=\(storage.count)")
        return true
    }

    /// Remove and return the highest-priority alert (FIFO within same priority).
    func dequeueNext() -> VoiceAlert? {
        guard !storage.isEmpty else { return nil }
        var bestIdx = 0
        for i in 1..<storage.count where storage[i].priority > storage[bestIdx].priority {
            bestIdx = i
        }
        return storage.remove(at: bestIdx)
    }

    /// Peek at the next alert without removing it.
    func peekNext() -> VoiceAlert? {
        storage.max(by: { $0.priority < $1.priority })
    }

    /// Cancel all queued alerts of a given priority.
    func cancel(priority: AlertPriority) {
        remove(reason: "cancelled p=\(priority)") { $0.priority == priority }
    }

    /// Cancel all queued alerts with a given alertKey.
    func cancel(alertKey: String) {
        remove(reason: "cancelled key=\(alertKey)") { $0.alertKey == alertKey }
    }

    /// Cancel all queued alerts.
    func cancelAll() {
        remove(reason: "cancelled all") { _ in true }
    }

    private func remove(reason: String, where shouldRemove: (VoiceAlert) -> Bool) {
        let removed = storage.filter(shouldRemove)
        guard !removed.isEmpty else { return }
        storage.removeAll(where: shouldRemove)
        for alert in removed {
            DiagnosticsLog.event("Voice", "\(reason): \(alert.logLabel)")
        }
    }
}
