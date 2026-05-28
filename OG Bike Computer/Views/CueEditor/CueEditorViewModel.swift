//
//  CueEditorViewModel.swift
//  OG Bike Computer
//
//  Drives the Cue Editor mode: holds the working CueEdits draft, the current
//  selection, and per-entry edit drafts (which persist across cancel so
//  re-opening the Add/Edit form restores in-progress data). Commits to the
//  RouteStore on each decisive action so the watch can resync.
//

import Foundation
import Combine
import CoreLocation

/// What the user sees as the row's resolved state. Computed from the working
/// CueEdits draft and the entry's kind.
enum CueEntryStatus: Equatable {
    case pending     // no decision yet
    case approved    // approved as-is, added (missingDetected), or edited
    case skipped     // user removed from the cue list
}

/// Display mode for the editor list.
enum CueEditorListMode: String {
    case sectioned   // 3 collapsible sections: Missing / Extra / Good
    case flat        // single list ordered by distance
}

/// Editable form state used by the Add (missingDetected) and Edit (waypoint) flows.
struct CueDraft: Equatable {
    /// Just the street/road name — primary edit target.
    var streetName: String = ""
    var direction: TurnDirection = .straight
    /// Optional full custom cue text (e.g. roundabout phrasings). Empty
    /// string = no override; falls back to substitution / compose template.
    var fullCueText: String = ""
}

@MainActor
final class CueEditorViewModel: ObservableObject {
    // MARK: - Inputs

    let route: Route
    private let routeStore: RouteStore
    /// Retained so the editor can look up per-turn data (e.g. inbound heading
    /// for map camera orientation) without re-processing the route.
    private let processed: ProcessedRoute

    /// Pre-classified buckets from the underlying route (does NOT consult edits).
    let classification: CueClassification

    /// All entries (sorted by distance) used by flat-list mode and lookups.
    let allEntries: [CueEntry]

    // MARK: - Working state

    /// The current overlay being edited. Committed to RouteStore on each change.
    @Published private(set) var edits: CueEdits

    /// Currently selected entry id (drives map zoom and inline form display).
    @Published var selection: CueEntryID?

    /// Display mode (sectioned vs flat).
    @Published var listMode: CueEditorListMode = .sectioned

    /// Section collapsed state for sectioned mode. Starts with all sections
    /// collapsed — the user opens the ones they want to work on.
    @Published var collapsedSections: Set<CueEntryKind> = [
        .missingDetected, .extra, .edit, .good
    ]

    /// Live form draft for the currently-selected entry (Add or Edit).
    /// Mirrors what's about to be committed if the user taps Save.
    @Published var draft: CueDraft = CueDraft()

    /// Persisted drafts across cancel: if the user cancels an Add, we remember
    /// what they typed so re-tapping + restores it. Keyed by entry id.
    @Published private(set) var rememberedDrafts: [CueEntryID: CueDraft] = [:]

    /// True while the user is actively filling in the Add form.
    @Published var isComposingAdd: Bool = false

    /// True while the user is actively editing an existing cue.
    @Published var isComposingEdit: Bool = false

    // MARK: - Init

    init(route: Route,
         processed: ProcessedRoute,
         routeStore: RouteStore) {
        self.route = route
        self.routeStore = routeStore
        self.processed = processed
        self.classification = CueDiff.classify(
            waypoints: processed.waypointTurnPoints,
            calculated: processed.calculatedTurnPoints
        )
        self.allEntries = classification.all
        // Start from whatever's already persisted (re-entering the editor).
        self.edits = route.cueEdits ?? CueEdits()
    }

    /// Bearing of the track approaching this turn, in degrees clockwise from
    /// north. Used to orient the map camera so the rider's heading-into-turn
    /// points "up".
    func inboundBearing(for entry: CueEntry) -> Double {
        let idx = entry.turn.index
        // Use the previous segment's bearing-to-next (the heading on the way
        // into the turn). Fall back to the turn's own bearing if at the start.
        let lookup = max(0, idx - 1)
        guard lookup < processed.points.count else { return 0 }
        return processed.points[lookup].bearingToNext
    }

    /// Bearing leaving the turn — the segment the rider takes onward.
    func outboundBearing(for entry: CueEntry) -> Double {
        let idx = min(max(0, entry.turn.index), processed.points.count - 1)
        return processed.points[idx].bearingToNext
    }

    /// Window of route coordinates centered on this turn, used to draw the
    /// highlight overlay. ±~40m by route distance to start; then if either
    /// endpoint sits within `chevronClearance` meters of the actual turn pin
    /// (dense GPS clusters around glitchy turns can stack endpoints on top of
    /// the pin), walk that endpoint outward one track point at a time until
    /// it crosses the threshold or runs off the end of the route.
    func highlightCoordinates(for entry: CueEntry) -> [CLLocationCoordinate2D] {
        let pts = processed.points
        guard !pts.isEmpty else { return [] }
        let turnIdx = entry.turn.index
        let center = entry.turn.distanceFromStart
        let halfWindow: Double = 40
        let chevronClearance: Double = 20  // meters between pin and either chevron

        // Initial bounds picked by along-route distance.
        var startIdx = pts.firstIndex { $0.distanceFromStart >= center - halfWindow }
            ?? max(0, turnIdx - 1)
        var endIdx = pts.lastIndex { $0.distanceFromStart <= center + halfWindow }
            ?? min(pts.count - 1, turnIdx + 1)

        // Guarantee at least one segment on each side of the turn.
        if startIdx >= turnIdx { startIdx = max(0, turnIdx - 1) }
        if endIdx <= turnIdx { endIdx = min(pts.count - 1, turnIdx + 1) }

        let turnLoc = CLLocation(
            latitude: entry.turn.coordinate.latitude,
            longitude: entry.turn.coordinate.longitude
        )

        // Walk outward from the initial window if the endpoint is too close to
        // the pin geographically (not just along route distance).
        while startIdx > 0 {
            let c = pts[startIdx].coordinate
            let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: turnLoc)
            if d >= chevronClearance { break }
            startIdx -= 1
        }
        while endIdx < pts.count - 1 {
            let c = pts[endIdx].coordinate
            let d = CLLocation(latitude: c.latitude, longitude: c.longitude).distance(from: turnLoc)
            if d >= chevronClearance { break }
            endIdx += 1
        }

        return (startIdx...endIdx).map { pts[$0].coordinate }
    }

    // MARK: - Derived

    /// Resolved status for an entry, blending its kind with the working edits.
    func status(for entry: CueEntry) -> CueEntryStatus {
        switch entry.id {
        case .waypoint(let id):
            guard let decision = edits.waypointDecisions[id] else { return .pending }
            return decision.status == .skipped ? .skipped : .approved
        case .detected(let idx):
            guard let decision = edits.detectedDecisions[idx] else { return .pending }
            // Dismissed means "reviewed, not adding" — render like Skipped (greyed).
            return decision.status == .approved ? .approved : .skipped
        }
    }

    /// True when the user has dealt with the entry one way or another.
    func isResolved(_ entry: CueEntry) -> Bool {
        status(for: entry) != .pending
    }

    /// Whether the entry has been overridden in some way (used for badges).
    func isCustomized(_ entry: CueEntry) -> Bool {
        switch entry.id {
        case .waypoint(let id):
            guard let d = edits.waypointDecisions[id] else { return false }
            return d.nameOverride != nil || d.directionOverride != nil
        case .detected(let idx):
            return edits.detectedDecisions[idx] != nil
        }
    }

    /// True once every entry has a decision — used to short-circuit auto-advance.
    var allResolved: Bool {
        allEntries.allSatisfy { isResolved($0) }
    }

    /// Resolved street name shown in the row and edit field. Override wins;
    /// otherwise we parse the current full cue text for a street name; final
    /// fallback is the full text itself (so the row never looks empty when
    /// there's text the parser didn't understand).
    func displayName(for entry: CueEntry) -> String? {
        switch entry.id {
        case .waypoint(let id):
            if let override = edits.waypointDecisions[id]?.nameOverride, !override.isEmpty {
                return override
            }
            let full = displayFullCue(for: entry)
            if let full = full, let parsed = CueTextParser.streetName(in: full) {
                return parsed
            }
            return full
        case .detected(let idx):
            if let override = edits.detectedDecisions[idx]?.name, !override.isEmpty {
                return override
            }
            // Missing-detected has no original cue text — parse the override
            // form if present, else return nil.
            if let full = displayFullCue(for: entry), let parsed = CueTextParser.streetName(in: full) {
                return parsed
            }
            return nil
        }
    }

    /// Resolved full cue text — what the watch would announce. Used as the
    /// advanced edit field's pre-fill / placeholder.
    func displayFullCue(for entry: CueEntry) -> String? {
        switch entry.id {
        case .waypoint(let id):
            let d = edits.waypointDecisions[id]
            if let custom = d?.fullCueOverride, !custom.isEmpty {
                return custom
            }
            if let name = d?.nameOverride, !name.isEmpty {
                if let original = entry.turn.description, !original.isEmpty {
                    return CueTextParser.substitute(in: original, with: name)
                }
                // No original to substitute into — compose from direction + name.
                return CueTextParser.compose(
                    direction: d?.directionOverride ?? entry.turn.direction,
                    streetName: name
                )
            }
            return entry.turn.description
        case .detected(let idx):
            let d = edits.detectedDecisions[idx]
            if let custom = d?.fullCueOverride, !custom.isEmpty {
                return custom
            }
            if let name = d?.name, !name.isEmpty {
                return CueTextParser.compose(
                    direction: d?.direction ?? entry.turn.direction,
                    streetName: name
                )
            }
            return nil
        }
    }

    /// What the cue WOULD resolve to using the values currently in the draft
    /// (street name + direction + full-cue override field). Drives the live
    /// placeholder in the Custom Cue Text field so the user can see the
    /// announcement update as they type a street name.
    func livePreviewFullCue(for entry: CueEntry) -> String? {
        let trimmedStreet = draft.streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFull = draft.fullCueText.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedFull.isEmpty { return trimmedFull }
        switch entry.id {
        case .waypoint:
            if !trimmedStreet.isEmpty {
                if let original = entry.turn.description, !original.isEmpty {
                    return CueTextParser.substitute(in: original, with: trimmedStreet)
                }
                return CueTextParser.compose(direction: draft.direction, streetName: trimmedStreet)
            }
            return entry.turn.description
        case .detected:
            if !trimmedStreet.isEmpty {
                return CueTextParser.compose(direction: draft.direction, streetName: trimmedStreet)
            }
            return nil
        }
    }

    /// Resolved direction (override or original).
    func displayDirection(for entry: CueEntry) -> TurnDirection {
        switch entry.id {
        case .waypoint(let id):
            return edits.waypointDecisions[id]?.directionOverride ?? entry.turn.direction
        case .detected(let idx):
            return edits.detectedDecisions[idx]?.direction ?? entry.turn.direction
        }
    }

    // MARK: - Selection / advance

    func select(_ id: CueEntryID?) {
        isComposingAdd = false
        isComposingEdit = false

        // When swapping from one turn to another, briefly clear the selection
        // and let SwiftUI/MapKit re-render before applying the new one. Without
        // this, the map annotation diffing keeps the old pin on top of the new
        // selection at overlapping (loop / double-back) spots.
        if let id = id, let current = selection, current != id {
            selection = nil
            DispatchQueue.main.async { [weak self] in
                self?.applySelection(id)
            }
            return
        }

        applySelection(id)
    }

    private func applySelection(_ id: CueEntryID?) {
        selection = id
        if let id = id, let entry = allEntries.first(where: { $0.id == id }) {
            draft = remembered(for: entry) ?? defaultDraft(for: entry)
        }
    }

    /// Pre-fill values for an entry's edit/add form — street name from the
    /// resolved name, direction from current display, full cue override only
    /// if the user has already set one (otherwise the field stays blank and
    /// the placeholder shows the generated text).
    private func defaultDraft(for entry: CueEntry) -> CueDraft {
        let street = displayName(for: entry) ?? ""
        let dir = displayDirection(for: entry)
        let fullOverride: String = {
            switch entry.id {
            case .waypoint(let id):
                return edits.waypointDecisions[id]?.fullCueOverride ?? ""
            case .detected(let idx):
                return edits.detectedDecisions[idx]?.fullCueOverride ?? ""
            }
        }()
        return CueDraft(streetName: street, direction: dir, fullCueText: fullOverride)
    }

    /// Move to the next pending entry in the current sort order; stop if all done.
    ///
    /// First clears the selection so the user can see the freshly-updated pin
    /// and row state for a beat, then advances to the next pending entry.
    private func advance(from id: CueEntryID) {
        let ordered = orderedEntriesForAdvance()
        guard let i = ordered.firstIndex(where: { $0.id == id }) else { return }
        let count = ordered.count

        var nextID: CueEntryID? = nil
        for step in 1...count {
            let next = ordered[(i + step) % count]
            if !isResolved(next) {
                nextID = next.id
                break
            }
        }

        // Deselect immediately to showcase the updated pin/row state.
        selection = nil

        // Brief pause, then move on — unless the user has manually selected
        // something else in the meantime.
        let target = nextID
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { [weak self] in
            guard let self = self else { return }
            guard self.selection == nil else { return }
            self.select(target)
        }
    }

    /// Walking order for auto-advance: in flat mode, by distance; in sectioned
    /// mode, follow the current section order (Missing → Extra → Good).
    private func orderedEntriesForAdvance() -> [CueEntry] {
        switch listMode {
        case .flat:
            return allEntries
        case .sectioned:
            return classification.missing + classification.extra + classification.good
        }
    }

    // MARK: - Actions: waypoints (Extra, Good, missing-name-only)

    /// Approve a waypoint cue as-is (or with whatever overrides have been set).
    func approveWaypoint(_ entry: CueEntry) {
        guard case let .waypoint(id) = entry.id else { return }
        var d = edits.waypointDecisions[id] ?? WaypointDecision(status: .approved)
        d.status = .approved
        edits.waypointDecisions[id] = d
        commit()
        advance(from: entry.id)
    }

    func skipWaypoint(_ entry: CueEntry) {
        guard case let .waypoint(id) = entry.id else { return }
        var d = edits.waypointDecisions[id] ?? WaypointDecision(status: .skipped)
        d.status = .skipped
        edits.waypointDecisions[id] = d
        commit()
        advance(from: entry.id)
    }

    /// Begin editing a waypoint's name/direction/full cue. Pre-fills the draft.
    /// For `.edit` entries (detector & cue disagreed on direction), the
    /// direction defaults to the detector's suggestion when the user hasn't
    /// already saved an override — that's the whole point of the Edit bucket.
    func beginEditWaypoint(_ entry: CueEntry) {
        guard case let .waypoint(id) = entry.id else { return }
        let hasDirectionOverride = edits.waypointDecisions[id]?.directionOverride != nil
        let suggestedDirection: TurnDirection = {
            if entry.kind == .edit, !hasDirectionOverride,
               let suggestion = entry.matchedCalculated?.direction {
                return suggestion
            }
            return displayDirection(for: entry)
        }()
        let baseDraft = defaultDraft(for: entry)
        draft = CueDraft(
            streetName: baseDraft.streetName,
            direction: suggestedDirection,
            fullCueText: baseDraft.fullCueText
        )
        isComposingEdit = true
    }

    /// Commit edits to a waypoint. Empty / unchanged fields clear their
    /// overrides so the original cue text is preserved.
    func saveEditWaypoint(_ entry: CueEntry) {
        guard case let .waypoint(id) = entry.id else { return }
        let originalDirection = entry.turn.direction
        let originalStreetName = entry.turn.description.flatMap(CueTextParser.streetName) ?? ""

        var d = edits.waypointDecisions[id] ?? WaypointDecision(status: .approved)

        let trimmedStreet = draft.streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFull = draft.fullCueText.trimmingCharacters(in: .whitespacesAndNewlines)

        d.directionOverride = (draft.direction == originalDirection) ? nil : draft.direction
        d.fullCueOverride = trimmedFull.isEmpty ? nil : trimmedFull
        d.nameOverride = (trimmedStreet.isEmpty || trimmedStreet == originalStreetName) ? nil : trimmedStreet
        d.status = .approved

        edits.waypointDecisions[id] = d
        isComposingEdit = false
        rememberedDrafts[entry.id] = draft
        commit()
        advance(from: entry.id)
    }

    func cancelEdit() {
        isComposingEdit = false
        if let id = selection, let entry = allEntries.first(where: { $0.id == id }) {
            draft = defaultDraft(for: entry)
        }
    }

    /// Drop any overrides on the current entry (revert to original values).
    /// Doesn't change approve/skip status.
    func resetEditsToOriginal(_ entry: CueEntry) {
        switch entry.id {
        case .waypoint(let id):
            if var d = edits.waypointDecisions[id] {
                d.nameOverride = nil
                d.directionOverride = nil
                d.fullCueOverride = nil
                edits.waypointDecisions[id] = d
            }
        case .detected:
            break
        }
        rememberedDrafts.removeValue(forKey: entry.id)
        draft = CueDraft(
            streetName: entry.turn.description.flatMap(CueTextParser.streetName) ?? "",
            direction: entry.turn.direction,
            fullCueText: ""
        )
        commit()
    }

    // MARK: - Actions: missing detected

    /// Open the Add form for a detected-only turn.
    func beginAdd(_ entry: CueEntry) {
        guard case .detected = entry.id else { return }
        draft = remembered(for: entry) ?? CueDraft(
            streetName: "",
            direction: entry.turn.direction,
            fullCueText: ""
        )
        isComposingAdd = true
    }

    /// Commit Add — promote a Missing detected turn to a real cue.
    func saveAdd(_ entry: CueEntry) {
        guard case let .detected(idx) = entry.id else { return }
        let trimmedStreet = draft.streetName.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedFull = draft.fullCueText.trimmingCharacters(in: .whitespacesAndNewlines)
        let decision = DetectedDecision(
            status: .approved,
            name: trimmedStreet.isEmpty ? nil : trimmedStreet,
            direction: draft.direction == entry.turn.direction ? nil : draft.direction,
            fullCueOverride: trimmedFull.isEmpty ? nil : trimmedFull
        )
        edits.detectedDecisions[idx] = decision
        rememberedDrafts[entry.id] = draft
        isComposingAdd = false
        commit()
        advance(from: entry.id)
    }

    /// Cancel an in-progress Add. Removes the approved decision (if any) but
    /// preserves the draft text for next time.
    func cancelAdd() {
        if let id = selection, case let .detected(idx) = id {
            rememberedDrafts[id] = draft
            edits.detectedDecisions.removeValue(forKey: idx)
            commit()
        }
        isComposingAdd = false
    }

    /// Wipe the remembered draft for the current entry.
    func clearDraft() {
        guard let id = selection else { return }
        rememberedDrafts.removeValue(forKey: id)
        if let entry = allEntries.first(where: { $0.id == id }) {
            draft = CueDraft(
                streetName: "",
                direction: entry.turn.direction,
                fullCueText: ""
            )
        }
    }

    /// Approve a Missing detected turn without adding it (= dismissed).
    func dismissMissing(_ entry: CueEntry) {
        guard case let .detected(idx) = entry.id else { return }
        edits.detectedDecisions[idx] = DetectedDecision(status: .dismissed)
        commit()
        advance(from: entry.id)
    }

    // MARK: - Section helpers

    func toggleSection(_ kind: CueEntryKind) {
        if collapsedSections.contains(kind) {
            collapsedSections.remove(kind)
        } else {
            collapsedSections.insert(kind)
        }
    }

    func isCollapsed(_ kind: CueEntryKind) -> Bool {
        collapsedSections.contains(kind)
    }

    // MARK: - Persistence

    private func commit() {
        routeStore.updateCueEdits(routeID: route.id, edits: edits)
    }

    private func remembered(for entry: CueEntry) -> CueDraft? {
        rememberedDrafts[entry.id]
    }
}
