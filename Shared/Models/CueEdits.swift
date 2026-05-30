//
//  CueEdits.swift
//  OG Bike Computer
//
//  Cue Editor overlay: the user's per-turn decisions layered on top of a route's
//  raw waypoint cues + algorithmically detected turns. Persisted alongside the
//  route; applied at ride time to produce the active cue list. The watch never
//  reads this structure directly — it consumes the resolved cue list only.
//

import Foundation

/// Decision on a waypoint-backed cue (Extra or Good, plus name-only-missing Goods).
struct WaypointDecision: Codable, Equatable {
    enum Status: String, Codable {
        case approved   // user agrees with the cue (possibly with overrides applied)
        case skipped    // user removed this cue from the final list
    }

    var status: Status
    /// Override just the street-name portion of the cue. The surrounding
    /// phrasing in the original description is preserved via substitution.
    /// nil = keep the original street name.
    var nameOverride: String?
    /// Override the waypoint's direction. nil = keep original.
    var directionOverride: TurnDirection?
    /// Optional full custom cue text. When set, replaces the entire
    /// description — used for unusual phrasings (e.g. roundabout cues) that
    /// don't match the standard "<verb> onto <street>" pattern. Takes
    /// precedence over nameOverride.
    var fullCueOverride: String?

    init(status: Status,
         nameOverride: String? = nil,
         directionOverride: TurnDirection? = nil,
         fullCueOverride: String? = nil) {
        self.status = status
        self.nameOverride = nameOverride
        self.directionOverride = directionOverride
        self.fullCueOverride = fullCueOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        nameOverride = try c.decodeIfPresent(String.self, forKey: .nameOverride)
        directionOverride = try c.decodeIfPresent(TurnDirection.self, forKey: .directionOverride)
        fullCueOverride = try c.decodeIfPresent(String.self, forKey: .fullCueOverride)
    }
}

/// Decision on a detector-only (Missing) turn: should we promote it to a cue?
struct DetectedDecision: Codable, Equatable {
    enum Status: String, Codable {
        case approved   // promote to cue (with optional name/direction)
        case dismissed  // user reviewed and explicitly chose not to add
    }

    var status: Status
    /// Street/road name to attach when promoted. The final cue text is
    /// generated as "<verb> onto <name>" unless fullCueOverride is set.
    var name: String?
    /// Optional direction override (default = detector's classification).
    var direction: TurnDirection?
    /// Optional full custom cue text. When set, replaces the generated cue.
    var fullCueOverride: String?

    init(status: Status,
         name: String? = nil,
         direction: TurnDirection? = nil,
         fullCueOverride: String? = nil) {
        self.status = status
        self.name = name
        self.direction = direction
        self.fullCueOverride = fullCueOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        name = try c.decodeIfPresent(String.self, forKey: .name)
        direction = try c.decodeIfPresent(TurnDirection.self, forKey: .direction)
        fullCueOverride = try c.decodeIfPresent(String.self, forKey: .fullCueOverride)
    }
}

/// A user-created turn cue anchored to a specific track-point on the route.
struct AddedCue: Codable, Equatable, Identifiable {
    let id: UUID
    /// Index into the route's track points where this cue snaps.
    var trackPointIndex: Int
    /// Street name (may be empty).
    var name: String
    var direction: TurnDirection
    /// Full custom cue text override; nil = compose from direction + name.
    var fullCueOverride: String?

    init(id: UUID = UUID(),
         trackPointIndex: Int,
         name: String = "",
         direction: TurnDirection = .straight,
         fullCueOverride: String? = nil) {
        self.id = id
        self.trackPointIndex = trackPointIndex
        self.name = name
        self.direction = direction
        self.fullCueOverride = fullCueOverride
    }
}

/// Decision on an imported POI waypoint — title/coordinate overrides + skip.
/// Skipping a POI hides it from the resolved route output.
struct POIDecision: Codable, Equatable {
    enum Status: String, Codable {
        case approved
        case skipped
    }

    var status: Status
    /// Override the POI's name. nil = keep original.
    var titleOverride: String?
    /// User-relocated coordinate. Either both lat/lon are nil (keep original)
    /// or both are set.
    var latitudeOverride: Double?
    var longitudeOverride: Double?

    init(status: Status,
         titleOverride: String? = nil,
         latitudeOverride: Double? = nil,
         longitudeOverride: Double? = nil) {
        self.status = status
        self.titleOverride = titleOverride
        self.latitudeOverride = latitudeOverride
        self.longitudeOverride = longitudeOverride
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        status = try c.decode(Status.self, forKey: .status)
        titleOverride = try c.decodeIfPresent(String.self, forKey: .titleOverride)
        latitudeOverride = try c.decodeIfPresent(Double.self, forKey: .latitudeOverride)
        longitudeOverride = try c.decodeIfPresent(Double.self, forKey: .longitudeOverride)
    }
}

/// A user-created POI waypoint. Free-form coordinate (not snapped to the route).
struct AddedPOI: Codable, Equatable, Identifiable {
    let id: UUID
    var lat: Double
    var lon: Double
    var name: String

    init(id: UUID = UUID(), lat: Double, lon: Double, name: String = "") {
        self.id = id
        self.lat = lat
        self.lon = lon
        self.name = name
    }
}

/// The full overlay attached to a Route.
struct CueEdits: Codable, Equatable {
    /// Decisions keyed by Waypoint.id.
    var waypointDecisions: [UUID: WaypointDecision]
    /// Decisions on detected turns, keyed by the detector's track-point index (stable
    /// as long as the underlying GPX track points don't change).
    var detectedDecisions: [Int: DetectedDecision]
    /// Overrides on imported POI waypoints, keyed by Waypoint.id.
    var poiDecisions: [UUID: POIDecision]
    /// User-created turn cues anchored to track-point indices.
    var addedCues: [AddedCue]
    /// User-created POI waypoints at arbitrary coordinates.
    var addedPOIs: [AddedPOI]

    init(waypointDecisions: [UUID: WaypointDecision] = [:],
         detectedDecisions: [Int: DetectedDecision] = [:],
         poiDecisions: [UUID: POIDecision] = [:],
         addedCues: [AddedCue] = [],
         addedPOIs: [AddedPOI] = []) {
        self.waypointDecisions = waypointDecisions
        self.detectedDecisions = detectedDecisions
        self.poiDecisions = poiDecisions
        self.addedCues = addedCues
        self.addedPOIs = addedPOIs
    }

    /// Backward-compatible decoding — older routes' CueEdits won't have the
    /// new collections.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        waypointDecisions = try c.decodeIfPresent([UUID: WaypointDecision].self, forKey: .waypointDecisions) ?? [:]
        detectedDecisions = try c.decodeIfPresent([Int: DetectedDecision].self, forKey: .detectedDecisions) ?? [:]
        poiDecisions = try c.decodeIfPresent([UUID: POIDecision].self, forKey: .poiDecisions) ?? [:]
        addedCues = try c.decodeIfPresent([AddedCue].self, forKey: .addedCues) ?? []
        addedPOIs = try c.decodeIfPresent([AddedPOI].self, forKey: .addedPOIs) ?? []
    }

    /// True if the user hasn't made any decisions yet — used to preserve legacy
    /// behavior for unedited routes.
    var isEmpty: Bool {
        waypointDecisions.isEmpty
            && detectedDecisions.isEmpty
            && poiDecisions.isEmpty
            && addedCues.isEmpty
            && addedPOIs.isEmpty
    }
}
