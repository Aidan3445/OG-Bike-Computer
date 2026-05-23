//
//  AlertPayload.swift
//  OG Bike Computer
//
//  The wire format for watch → phone voice alerts. The watch decides what
//  to say and the phone synthesizes it locally — text crosses the link,
//  not audio (see plan §1, §2.5).
//
//  Three transport priorities map to WCSession methods:
//   • .immediate  → WCSession.sendMessage(replyHandler:errorHandler:)
//                   Used for turn-now, hazard, off-route, back-on-route,
//                   immediate-turn. Requires reachability; raced against a
//                   short fallback timer on the watch.
//   • .soon       → WCSession.transferUserInfo(_:)
//                   Used for queued non-urgent alerts (approach distance
//                   warnings, splits). Guaranteed delivery without requiring
//                   reachability; the phone speaks when it gets to it.
//   • .background → WCSession.updateApplicationContext(_:)
//                   Last-write-wins state sync (not used for alerts yet, but
//                   defined here so the schema is complete).
//
//  Encoded as a property-list dictionary because WCSession's payload types
//  must be plist-compatible. Use `toDict` / `fromDict` rather than JSON.
//

import Foundation

enum AlertTransportPriority: String, Codable, Hashable {
    case immediate   // sendMessage path — sub-second delivery wanted
    case soon        // transferUserInfo path — queued, delivered when possible
    case background  // applicationContext path — last-write-wins state
}

/// Functional categorization of an alert. Watch and phone both know what
/// kind of thing a payload represents; useful for telemetry, notification
/// posting on the phone, and priority interruption logic on the watch.
enum AlertKind: String, Codable, Hashable {
    case turnApproach    // "in 400 feet, turn left"
    case turnImmediate   // "turn left now"
    case offRoute        // "off route"
    case backOnRoute     // "back on route. left to continue."
    case lastTurn        // "last turn complete. 200m to finish."
    case arrival         // "you have arrived"
    case halfway         // "halfway point"
    case split           // "1 mile split N. time 4:23. average speed 14 mph."
    case autoPause       // "auto paused" / "resumed"
    case waypoint        // POI announcement
    case info            // generic — anything else
}

struct AlertPayload: Codable, Hashable {
    /// Unique per alert. Used for dedupe on receive, ack matching, and
    /// fallback-timer cancellation on the watch side.
    let id: UUID
    let kind: AlertKind
    let priority: AlertTransportPriority
    let text: String
    /// Watch's wall-clock at decision time. Used by the phone for latency
    /// telemetry and by the stale-drop filter.
    let createdAt: Date
    /// Drop on receive if `Date() > expiresAt`. Prevents speaking a stale
    /// alert that was queued by transferUserInfo and only just arrived.
    let expiresAt: Date

    init(
        id: UUID = UUID(),
        kind: AlertKind,
        priority: AlertTransportPriority,
        text: String,
        createdAt: Date = Date(),
        ttl: TimeInterval = 15
    ) {
        self.id = id
        self.kind = kind
        self.priority = priority
        self.text = text
        self.createdAt = createdAt
        self.expiresAt = createdAt.addingTimeInterval(ttl)
    }

    // MARK: - WCSession dict encoding
    //
    // WatchConnectivity payloads must be plist-compatible types (String,
    // Number, Bool, Date, Data, Array, Dictionary). We hand-encode rather
    // than going through JSON because (a) it's smaller over the wire and
    // (b) Date and UUID round-trip cleanly without ISO-string conversion.

    private enum WireKey {
        static let type = "type"            // discriminator vs other WC messages
        static let id = "id"
        static let kind = "kind"
        static let priority = "priority"
        static let text = "text"
        static let createdAt = "createdAt"
        static let expiresAt = "expiresAt"
    }

    /// Discriminator written into the `type` field so message receivers
    /// can route this payload past other WC messages on the same channel.
    static let messageType = "voiceAlert"

    /// Encode for WCSession transport. Includes the `type` discriminator so
    /// the receiver's switch on `message["type"]` matches.
    func toDict() -> [String: Any] {
        [
            WireKey.type: Self.messageType,
            WireKey.id: id.uuidString,
            WireKey.kind: kind.rawValue,
            WireKey.priority: priority.rawValue,
            WireKey.text: text,
            WireKey.createdAt: createdAt,
            WireKey.expiresAt: expiresAt
        ]
    }

    /// Decode from a WCSession-delivered dictionary. Returns nil when any
    /// required field is missing or malformed — the receiver should drop
    /// in that case rather than guessing.
    static func fromDict(_ dict: [String: Any]) -> AlertPayload? {
        guard
            (dict[WireKey.type] as? String) == messageType,
            let idStr = dict[WireKey.id] as? String,
            let id = UUID(uuidString: idStr),
            let kindStr = dict[WireKey.kind] as? String,
            let kind = AlertKind(rawValue: kindStr),
            let priorityStr = dict[WireKey.priority] as? String,
            let priority = AlertTransportPriority(rawValue: priorityStr),
            let text = dict[WireKey.text] as? String,
            let createdAt = dict[WireKey.createdAt] as? Date,
            let expiresAt = dict[WireKey.expiresAt] as? Date
        else {
            return nil
        }
        return AlertPayload(
            id: id,
            kind: kind,
            priority: priority,
            text: text,
            createdAt: createdAt,
            ttl: max(0, expiresAt.timeIntervalSince(createdAt))
        )
    }
}

// MARK: - Ack envelope

/// Phone → watch ack. Sent via WCSession.sendMessage when the phone's
/// AVSpeechSynthesizer fires `didStart` for the matching utterance. This
/// is the signal the watch uses to cancel its FallbackTimer for the same
/// alert id — receipt of this ack means "phone is speaking, don't speak
/// locally."
struct AlertAck {
    static let messageType = "voiceAlertAck"

    let id: UUID

    func toDict() -> [String: Any] {
        [
            "type": Self.messageType,
            "id": id.uuidString,
            "ts": Date()
        ]
    }

    static func fromDict(_ dict: [String: Any]) -> AlertAck? {
        guard
            (dict["type"] as? String) == messageType,
            let idStr = dict["id"] as? String,
            let id = UUID(uuidString: idStr)
        else { return nil }
        return AlertAck(id: id)
    }
}
