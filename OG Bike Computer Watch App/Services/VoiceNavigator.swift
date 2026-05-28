//
//  VoiceNavigator.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import AVFoundation
import CoreLocation
import Combine
import UserNotifications

class VoiceNavigator: NSObject, ObservableObject {
    static let shared = VoiceNavigator()

    @Published var isEnabled = true

    var preferences: NavigationAlertPreferences = .default

    private var alertDistances: [Double] {
        preferences.turnAlerts.alertDistances
    }
    private let groupTurnThreshold: Double = 150 // meters between turns to group them

    private let atTurnThreshold: Double = 20
    private let cooldown: TimeInterval = 4
    private let minTimeBeforeTurn: TimeInterval = 4

    // State
    private var isActivelyMoving = true
    private var currentTurnIndex: Int?
    private var firedTurnAlerts: Set<Int> = []
    private var groupedApproachTurnIndices: Set<Int> = []

    private var trackingFinish = false
    private var firedFinishAlerts: Set<Int> = []

    private var announcedHalfway = false
    private var seenBeforeHalfway = false  // guards against firing halfway if rider started past that point
    private var announcedArrival = false
    private var announcedOffRoute = false

    /// Keys of POI alerts already fired this ride. Keyed as
    /// `"<poiIndex>-<tierDistance>"` so each POI fires at most once per tier.
    private var firedPOIAlerts: Set<String> = []

    private var wasOffRoute = false
    private var lastAnnouncementTime: Date = .distantPast
    private var lastTurnAlertTime: Date = .distantPast

    // Prevents any speech after stop
    private var isStopped = false
    private var pendingWorkItem: DispatchWorkItem?

    // Alert queue
    private let alertQueue = VoiceAlertQueue()
    private var isProcessingAlert = false

    // Identity of the alert currently in-flight on VoiceAlertTransport.
    // Used to ignore late completions for an alert that's been superseded
    // (e.g. ride reset cancelled all in-flight, but a stray completion
    // races back to us afterward).
    private var inFlightAlertID: UUID?

    // Recreated each ride to avoid AVSpeechSynthesizer silent-death bug
    private var synthesizer: AVSpeechSynthesizer
    weak var workoutManager: WorkoutManager?

    private override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func reset() {
        isStopped = true

        pendingWorkItem?.cancel()
        pendingWorkItem = nil

        currentTurnIndex = nil
        firedTurnAlerts.removeAll()
        groupedApproachTurnIndices.removeAll()
        trackingFinish = false
        firedFinishAlerts.removeAll()
        announcedHalfway = false
        seenBeforeHalfway = false
        announcedArrival = false
        announcedOffRoute = false
        firedPOIAlerts.removeAll()

        wasOffRoute = false
        lastAnnouncementTime = .distantPast
        lastTurnAlertTime = .distantPast

        alertQueue.cancelAll()
        isProcessingAlert = false
        clearInFlight()

        synthesizer.stopSpeaking(at: .immediate)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)

        // Fresh synthesizer for next ride
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    func resetForRouteSwap() {
        currentTurnIndex = nil
        firedTurnAlerts.removeAll()
        groupedApproachTurnIndices.removeAll()
        trackingFinish = false
        firedFinishAlerts.removeAll()
        announcedHalfway = false
        seenBeforeHalfway = false
        announcedArrival = false
        announcedOffRoute = false
        firedPOIAlerts.removeAll()

        wasOffRoute = false
        lastAnnouncementTime = .distantPast
        lastTurnAlertTime = .distantPast

        alertQueue.cancel(priority: .turnApproach)
        alertQueue.cancel(priority: .immediateTurn)
        alertQueue.cancel(priority: .navEvent)
    }

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetoothHFP, .allowBluetoothA2DP])
        } catch {
            print("VoiceNavigator audio session config error: \(error)")
        }
        // Must come AFTER reset()
        isStopped = false
    }

    func update(nav: NavigationTracker, speed: Double, heading: Double = 0, isActivelyMoving: Bool = true) {
        guard isEnabled, !isStopped else { return }
        guard let route = nav.processedRoute else { return }

        self.isActivelyMoving = isActivelyMoving

        let navEvents = preferences.navigationEvents

        if nav.isRouteComplete {
            if !announcedArrival {
                announcedArrival = true
                enqueueAlert(VoiceAlert(
                    priority: .navEvent,
                    text: "You have arrived. Route complete.",
                    mode: navEvents.arrivalAlert,
                    category: "arrival",
                    alertKey: "arrival"
                ))
                announceEndOfRouteStats()
            }
            return
        }

        if nav.isOffRoute {
            if !announcedOffRoute {
                announcedOffRoute = true
                let text: String
                if let missed = nav.missedTurn {
                    text = "Off route. Missed \(missed.direction.voiceLabel2)."
                } else {
                    text = "Off route."
                }
                enqueueAlert(VoiceAlert(
                    priority: .navEvent,
                    text: text,
                    mode: navEvents.offRouteAlert,
                    category: "offRoute",
                    alertKey: "route-state",
                    mutualCancelKey: "route-state",
                    // Drop if the rider has already rejoined the route by
                    // the time the queue gets to this alert.
                    relevanceCheck: { [weak self] in
                        self?.workoutManager?.navigation.isOffRoute == true
                    }
                ))
            }
            wasOffRoute = true
            return
        } else if wasOffRoute {
            wasOffRoute = false
            announcedOffRoute = false

            // Prime turn tracking at the rejoin position so the next update doesn't
            // immediately fire a stale approach alert for the turn the rider is now near.
            if let turn = nav.nextTurn {
                currentTurnIndex = turn.index
                firedTurnAlerts.removeAll()
                markPassedThresholds(distance: nav.distanceToNextTurn, into: &firedTurnAlerts)
            }

            let routeBearing = nav.currentBearing
            let continueDirection = voiceDirectionToTarget(heading: heading, bearingToTarget: routeBearing)
            let backOnRouteText: String
            if continueDirection == "continue straight" {
                backOnRouteText = "Back on route."
            } else {
                backOnRouteText = "Back on route. \(continueDirection.capitalized)."
            }
            enqueueAlert(VoiceAlert(
                priority: .navEvent,
                text: backOnRouteText,
                mode: navEvents.backOnRouteAlert,
                category: "backOnRoute",
                alertKey: "route-state",
                mutualCancelKey: "route-state",
                // Drop if we've gone off-route again before this even spoke.
                relevanceCheck: { [weak self] in
                    self?.workoutManager?.navigation.isOffRoute == false
                }
            ))
            return
        }

        if let turn = nav.nextTurn, turn.index != currentTurnIndex {
            let passedTurn = currentTurnIndex != nil

            // Cancel stale approach alert for the turn we just passed
            if let oldIndex = currentTurnIndex {
                alertQueue.cancel(alertKey: "turn-approach-\(oldIndex)")
            }

            currentTurnIndex = turn.index
            firedTurnAlerts.removeAll()
            // Keep turn.index in groupedApproachTurnIndices if it's there — the
            // approach suppression and direction-only at-turn text both rely on
            // it persisting until the at-turn alert fires.
            trackingFinish = false
            firedFinishAlerts.removeAll()

            if passedTurn {
                if isActivelyMoving {
                    // Skip a fresh approach alert when this turn was already
                    // named in the prior compound ("…then turn left onto Main").
                    // The at-turn alert below still fires (direction-only).
                    if !groupedApproachTurnIndices.contains(turn.index) {
                        let dist = nav.distanceToNextTurn
                        let followingTurn = nav.nearbyFollowingTurn(after: turn)

                        let text: String
                        if let ft = followingTurn {
                            groupedApproachTurnIndices.insert(ft.index)
                            text = "in \(formatVoiceDistance(dist)), \(voiceText(for: turn)) then \(followingTurnPhrase(for: ft))."
                        } else {
                            text = "in \(formatVoiceDistance(dist)), \(voiceText(for: turn))."
                        }
                        enqueueAlert(VoiceAlert(
                            priority: .turnApproach,
                            text: text,
                            mode: preferences.turnAlerts.mode(forAlertIndex: 0, totalCount: alertDistances.count),
                            category: "turnApproach",
                            alertKey: "turn-approach-\(turn.index)",
                            relevanceCheck: { [weak self] in
                                self?.currentTurnIndex == turn.index
                            }
                        ))
                        lastTurnAlertTime = Date()
                        markPassedThresholds(distance: dist, into: &firedTurnAlerts)
                    }
                }
                return
            }
        }

        if let turn = nav.nextTurn {
            let approachSuppressed = groupedApproachTurnIndices.contains(turn.index)
            let followingTurn = nav.nearbyFollowingTurn(after: turn)

            if fireDistanceAlert(
                distance: nav.distanceToNextTurn,
                speed: speed,
                fired: &firedTurnAlerts,
                suppressApproach: approachSuppressed,
                turnIndex: turn.index,
                atZeroText: "\(self.atTurnText(for: turn).localizedCapitalized).",
                approachText: { d in
                    if let ft = followingTurn {
                        self.groupedApproachTurnIndices.insert(ft.index)
                        return "in \(formatVoiceDistance(d)), \(self.voiceText(for: turn)) then \(self.followingTurnPhrase(for: ft))."
                    }
                    return "in \(formatVoiceDistance(d)), \(self.voiceText(for: turn))."
                }
            ) { return }

            let isLastTurn = nav.activeTurnPoints.last?.index == turn.index
            if isLastTurn, firedTurnAlerts.contains(alertDistances.count - 1) {
                if !trackingFinish {
                    trackingFinish = true
                    firedFinishAlerts.removeAll()
                    let remaining = nav.distanceRemaining
                    if remaining > atTurnThreshold, isActivelyMoving {
                        enqueueAlert(VoiceAlert(
                            priority: .navEvent,
                            text: "Last turn complete. \(formatVoiceDistance(remaining)) to finish."
                        ))
                        markPassedThresholds(distance: remaining, into: &firedFinishAlerts)
                        return
                    }
                }
            }
        }

        if nav.nextTurn == nil, !nav.isRouteComplete {
            if !trackingFinish {
                trackingFinish = true
                firedFinishAlerts.removeAll()
                let remaining = nav.distanceRemaining
                if isActivelyMoving {
                    enqueueAlert(VoiceAlert(
                        priority: .navEvent,
                        text: "Last turn complete. \(formatVoiceDistance(remaining)) to finish."
                    ))
                    markPassedThresholds(distance: remaining, into: &firedFinishAlerts)
                }
                return
            }

            if fireDistanceAlert(
                distance: nav.distanceRemaining,
                speed: speed,
                fired: &firedFinishAlerts,
                atZeroText: "You have arrived. Route complete.",
                approachText: { d in "Finish \(formatVoiceDistance(d))." },
                isTurnAlert: false
            ) { return }
        }

        if !announcedHalfway {
            let half = route.totalDistance / 2
            // Track that the rider was on the first half so we don't fire halfway
            // if they started mid-route or resumed a hold past the halfway point.
            if nav.distanceAlongRoute < half {
                seenBeforeHalfway = true
            }
            if seenBeforeHalfway && nav.distanceAlongRoute >= half {
                announcedHalfway = true
                if isActivelyMoving {
                    announceHalfway(distanceRemaining: nav.distanceRemaining, mode: navEvents.halfwayAlert)
                }
                return
            }
        }

        if isActivelyMoving {
            checkPOIAlerts(nav: nav, route: route)
        }
    }

    // MARK: - POI / Waypoint Announcements

    private func checkPOIAlerts(nav: NavigationTracker, route: ProcessedRoute) {
        let prefs = preferences.waypointAlerts
        guard prefs.enabled, prefs.mode != .none, !route.pois.isEmpty else { return }

        // Tiers descending (largest distance first) so we pick the earliest
        // tier the rider has just crossed.
        var tiers: [Double] = []
        if prefs.useCustomDistances {
            if prefs.secondaryApproachEnabled {
                tiers.append(prefs.secondaryApproachDistance)
            }
            tiers.append(prefs.primaryApproachDistance)
        } else {
            let turn = preferences.turnAlerts
            if turn.secondaryApproachEnabled {
                tiers.append(turn.secondaryApproachDistance)
            }
            tiers.append(turn.primaryApproachDistance)
        }
        tiers.sort(by: >)
        guard !tiers.isEmpty else { return }

        for (idx, poi) in route.pois.enumerated() {
            if poi.offRouteDistance > prefs.maxOffRouteDistance { continue }
            let ahead = poi.distanceFromStart - nav.distanceAlongRoute
            guard ahead > 0 else { continue }

            for tier in tiers {
                guard ahead <= tier else { continue }
                let key = "\(idx)-\(Int(tier))"
                if firedPOIAlerts.contains(key) { continue }
                firedPOIAlerts.insert(key)
                let text = poiText(poi: poi, ahead: ahead, route: route)
                enqueueAlert(VoiceAlert(
                    priority: .stat,
                    text: text,
                    mode: prefs.mode,
                    category: "poi"
                ))
                break
            }
        }
    }

    private func poiText(poi: RoutePOI, ahead: Double, route: ProcessedRoute) -> String {
        let distancePhrase = formatVoiceDistance(ahead)
        // POIs essentially on the route ("pass …"); else "is …" with bearing.
        let onRouteThreshold: Double = 30
        if poi.offRouteDistance <= onRouteThreshold {
            return "in \(distancePhrase), pass \(poi.name)."
        }
        let offPhrase = formatVoiceDistance(poi.offRouteDistance)
        if let side = poiSide(poi: poi, route: route) {
            return "in \(distancePhrase) to your \(side), \(offPhrase) off route, is \(poi.name)."
        }
        return "in \(distancePhrase), \(offPhrase) off route, is \(poi.name)."
    }

    private func poiSide(poi: RoutePOI, route: ProcessedRoute) -> String? {
        guard poi.nearestPointIndex >= 0, poi.nearestPointIndex < route.points.count else { return nil }
        let basePoint = route.points[poi.nearestPointIndex]
        let routeBearing = basePoint.bearingToNext
        let poiBearing = poiBearingDegrees(from: basePoint.coordinate, to: poi.coordinate)
        var relative = poiBearing - routeBearing
        while relative > 180 { relative -= 360 }
        while relative < -180 { relative += 360 }
        if Swift.abs(relative) < 10 || Swift.abs(relative) > 170 { return nil }
        return relative > 0 ? "right" : "left"
    }

    private func poiBearingDegrees(from a: CLLocationCoordinate2D, to b: CLLocationCoordinate2D) -> Double {
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let brng = atan2(y, x) * 180 / .pi
        return (brng + 360).truncatingRemainder(dividingBy: 360)
    }

    /// At-turn spoken text. When the turn was already named in a prior
    /// compound approach alert ("…then turn left onto Main"), drop the
    /// street name and speak the direction only so the rider doesn't hear
    /// the same name three times in 30 seconds.
    private func atTurnText(for turn: TurnPoint) -> String {
        if groupedApproachTurnIndices.contains(turn.index) {
            return turn.direction.voiceLabel
        }
        return voiceText(for: turn)
    }

    private func voiceText(for turn: TurnPoint) -> String {
        guard let desc = turn.description, !desc.isEmpty else {
            return turn.direction.voiceLabel
        }

        let pronounced = applyRoadNamePronunciation(desc)
        let lower = pronounced.lowercased()

        if lower.hasPrefix("make a ") {
            return String(pronounced.dropFirst(7))
        }
        return pronounced
    }

    /// Builds the spoken phrase for the *following* turn in a multi-turn announcement.
    /// Returns `"<direction>"` or `"<direction> onto <name>"` when a name is available.
    private func followingTurnPhrase(for ft: TurnPoint) -> String {
        let dir = ft.direction.voiceLabel
        guard let desc = ft.description,
              let r = desc.range(of: " onto ", options: .caseInsensitive) else {
            return dir
        }
        let name = String(desc[r.upperBound...]).trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return dir }
        return "\(dir) onto \(applyRoadNamePronunciation(name))"
    }

    /// Applies highway/road-name pronunciation hints to a turn description so TTS reads
    /// route shields and abbreviations the way a rider expects:
    /// - "US 17" / "PA 106" / "I 95" → spelled letters ("U S 17", "P A 106", "I 95")
    /// - Trailing single direction letter ("Main St N") → compass word ("Main Street north")
    /// - "St."/"St" disambiguation: first token (or post-comma) → "Saint", otherwise → "Street"
    /// Operates on the post-"onto " portion when present so the "Turn right onto …" prefix is
    /// left untouched.
    fileprivate func applyRoadNamePronunciation(_ text: String) -> String {
        let prefix: String
        let namePart: String
        if let r = text.range(of: " onto ", options: .caseInsensitive) {
            prefix = String(text[..<r.upperBound])
            namePart = String(text[r.upperBound...])
        } else {
            prefix = ""
            namePart = text
        }

        var tokens = namePart.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !tokens.isEmpty else { return text }

        // Two-cap-letter route shield prefix followed by a number.
        if tokens.count >= 2 {
            let first = tokens[0]
            let upper = first.uppercased()
            let isAllLetters = first.unicodeScalars.allSatisfy { CharacterSet.letters.contains($0) }
            let nextStartsWithNumber = tokens[1].first.map(\.isNumber) ?? false
            if first == upper, isAllLetters, first.count >= 1, first.count <= 2, nextStartsWithNumber {
                tokens[0] = upper.map { String($0) }.joined(separator: " ")
            }
        }

        // Trailing direction letter.
        if tokens.count >= 2 {
            switch tokens[tokens.count - 1].uppercased() {
            case "N": tokens[tokens.count - 1] = "north"
            case "S": tokens[tokens.count - 1] = "south"
            case "E": tokens[tokens.count - 1] = "east"
            case "W": tokens[tokens.count - 1] = "west"
            default: break
            }
        }

        // ST. / ST disambiguation.
        for i in tokens.indices {
            let stripped = tokens[i].replacingOccurrences(of: ".", with: "").uppercased()
            guard stripped == "ST" else { continue }
            let isFirst = (i == 0)
            let afterComma = (i > 0 && tokens[i - 1].hasSuffix(","))
            tokens[i] = (isFirst || afterComma) ? "Saint" : "Street"
        }

        return prefix + tokens.joined(separator: " ")
    }

    private func fireDistanceAlert(
        distance: Double,
        speed: Double,
        fired: inout Set<Int>,
        suppressApproach: Bool = false,
        turnIndex: Int? = nil,
        atZeroText: String,
        approachText: (Double) -> String,
        isTurnAlert: Bool = true
    ) -> Bool {
        let distances = alertDistances
        for (i, alertDist) in distances.enumerated() {
            guard !fired.contains(i) else { continue }

            let isAtTurn = alertDist == 0
            let threshold = isAtTurn ? atTurnThreshold : alertDist
            guard distance <= threshold else { continue }

            let mode: AlertMode = isTurnAlert
                ? preferences.turnAlerts.mode(forAlertIndex: i, totalCount: distances.count)
                : .voiceAndHaptic

            if mode == .none {
                fired.insert(i)
                continue
            }

            if !isAtTurn && !isActivelyMoving { continue }

            if !isAtTurn && suppressApproach {
                fired.insert(i)
                continue
            }

            if !isAtTurn && isTurnAlert && distance > 200 {
                let gap = Date().timeIntervalSince(lastTurnAlertTime)
                if gap < preferences.turnAlerts.minimumAlertGap {
                    fired.insert(i)
                    continue
                }
            }

            if !isAtTurn && !canSpeak { continue }

            if !isAtTurn, speed > 0.5 {
                let timeToTarget = distance / speed
                if timeToTarget < minTimeBeforeTurn {
                    fired.insert(i)
                    continue
                }
            }

            fired.insert(i)

            let text = isAtTurn ? atZeroText : approachText(distance)
            let cat = isTurnAlert ? (isAtTurn ? "atTurn" : "turnApproach") : nil

            if isTurnAlert, let idx = turnIndex {
                if isAtTurn {
                    enqueueAlert(VoiceAlert(
                        priority: .immediateTurn,
                        text: text,
                        mode: mode,
                        category: cat,
                        alertKey: "turn-immediate-\(idx)",
                        replacesKey: "turn-approach-\(idx)",
                        // Drop if the rider has already moved past this turn
                        // (e.g. queue was blocked behind a long stat readout
                        // and the rider missed it — announcing "turn left"
                        // 5s late is misleading; the off-route flow will
                        // catch it instead).
                        relevanceCheck: { [weak self] in
                            self?.currentTurnIndex == idx
                        }
                    ))
                } else {
                    enqueueAlert(VoiceAlert(
                        priority: .turnApproach,
                        text: text,
                        mode: mode,
                        category: cat,
                        alertKey: "turn-approach-\(idx)",
                        // Drop stale approach alerts for turns we've moved past.
                        relevanceCheck: { [weak self] in
                            self?.currentTurnIndex == idx
                        }
                    ))
                }
            } else {
                let priority: AlertPriority = isAtTurn ? .immediateTurn : .turnApproach
                enqueueAlert(VoiceAlert(priority: priority, text: text, mode: mode, category: cat))
            }

            if isTurnAlert { lastTurnAlertTime = Date() }
            return true
        }
        return false
    }

    private var canSpeak: Bool {
        Date().timeIntervalSince(lastAnnouncementTime) >= cooldown
    }

    private func markPassedThresholds(distance: Double, into set: inout Set<Int>) {
        for (i, d) in alertDistances.enumerated() {
            let threshold = d == 0 ? atTurnThreshold : d
            if distance <= threshold {
                set.insert(i)
            }
        }
    }

    /// Callback for haptic feedback — set by WorkoutManager
    var onHaptic: ((AlertMode) -> Void)?

    // MARK: - Auto-Pause Alerts

    func announceAutoPause(mode: AlertMode) {
        enqueueAlert(VoiceAlert(
            priority: .autoPause,
            text: "Auto paused.",
            mode: mode,
            category: "autoPause",
            alertKey: "pause-state",
            mutualCancelKey: "pause-state"
        ))
    }

    func announceAutoResume(mode: AlertMode) {
        enqueueAlert(VoiceAlert(
            priority: .autoPause,
            text: "Resumed.",
            mode: mode,
            category: "autoResume",
            alertKey: "pause-state",
            mutualCancelKey: "pause-state"
        ))
    }

    // MARK: - Split / Halfway Announcements

    func announceSplit(number: Int, splitDistance: Double, splitStats: SplitStats, rideStats: SplitStats, metrics: [SplitMetricConfig], mode: AlertMode) {
        let orderedMetrics = metrics

        let header = "\(formatVoiceDistance(splitDistance)) split \(number)."
        enqueueAlert(VoiceAlert(priority: .stat, text: header, mode: mode, category: "lap"))

        for config in orderedMetrics {
            let splitVal = statText(for: config.metric, from: splitStats, label: "")
            let rideVal = statText(for: config.metric, from: rideStats, label: "")

            switch config.scope {
            case .split:
                if let sv = splitVal {
                    enqueueAlert(VoiceAlert(priority: .stat, text: sv, mode: mode, category: "lap"))
                }
            case .ride:
                if let rv = rideVal {
                    enqueueAlert(VoiceAlert(priority: .stat, text: "ride \(rv)", mode: mode, category: "lap"))
                }
            case .both:
                if let sv = splitVal {
                    enqueueAlert(VoiceAlert(priority: .stat, text: sv, mode: mode, category: "lap"))
                }
                if let rv = rideVal {
                    enqueueAlert(VoiceAlert(priority: .stat, text: "ride \(rv)", mode: mode, category: "lap"))
                }
            }
        }
    }

    private func announceEndOfRouteStats() {
        let prefs = preferences.endOfRouteAlerts
        guard prefs.enabled, let wm = workoutManager else { return }

        let metrics: [SplitMetricConfig]
        if prefs.useSplitsMetrics {
            metrics = preferences.splitAlerts.metrics
        } else {
            metrics = prefs.metricsOverride ?? preferences.splitAlerts.metrics
        }
        guard !metrics.isEmpty else { return }

        let rideStats = wm.currentRideStats()
        var prefixApplied = false
        for config in metrics {
            let prefix = prefixApplied ? "" : "ride "
            if let text = statText(for: config.metric, from: rideStats, label: prefix) {
                enqueueAlert(VoiceAlert(priority: .stat, text: text, mode: prefs.mode, category: "endOfRoute"))
                prefixApplied = true
            }
        }
    }

    private func announceHalfway(distanceRemaining: Double, mode: AlertMode) {
        let header = "Halfway point. \(formatVoiceDistance(distanceRemaining)) to go."
        enqueueAlert(VoiceAlert(priority: .stat, text: header, mode: mode, category: "halfway"))

        if let wm = workoutManager {
            let splitPrefs = preferences.splitAlerts
            if splitPrefs.enabled, !splitPrefs.metrics.isEmpty {
                let halfStats = wm.currentRideStats()
                let orderedMetrics = splitPrefs.metrics
                // Only the first stat gets the "first half" prefix — once the
                // rider has the scope, subsequent readings inherit it.
                var prefixApplied = false
                for config in orderedMetrics {
                    let prefix = prefixApplied ? "" : "first half "
                    if let text = statText(for: config.metric, from: halfStats, label: prefix) {
                        enqueueAlert(VoiceAlert(priority: .stat, text: text, mode: mode, category: "halfway"))
                        prefixApplied = true
                    }
                }
            }
        }
    }

    /// Build a spoken phrase for `metric` from `stats`, prefixed by `label`
    /// (e.g. "split ", "ride ", "first half "). Returns nil when there's no
    /// meaningful value (e.g. zero max HR — never had any HR data).
    private func statText(for metric: MetricType, from stats: SplitStats, label: String) -> String? {
        switch metric {
        case .movingTime:
            return "\(label)time \(formatVoiceDuration(stats.movingTime))"
        case .elapsedTime:
            return "\(label)elapsed \(formatVoiceDuration(stats.elapsedTime))"
        case .averageSpeed:
            return "\(label)average speed \(formatVoiceSpeed(stats.averageSpeed))"
        case .maxSpeed:
            guard stats.maxSpeed > 0 else { return nil }
            return "\(label)max speed \(formatVoiceSpeed(stats.maxSpeed))"
        case .distance:
            return "\(label)distance \(formatVoiceDistance(stats.distance))"
        case .heartRate, .averageHeartRate:
            // .heartRate kept as alias for back-compat with old saved configs.
            guard stats.averageHeartRate > 0 else { return nil }
            return "\(label)average heart rate \(Int(stats.averageHeartRate)) beats per minute"
        case .maxHeartRate:
            guard stats.maxHeartRate > 0 else { return nil }
            return "\(label)max heart rate \(Int(stats.maxHeartRate)) beats per minute"
        case .elevationGain:
            guard stats.elevationGain > 0 else { return nil }
            return "\(label)elevation gain \(formatVoiceElevation(stats.elevationGain))"
        case .elevationLoss:
            guard stats.elevationLoss > 0 else { return nil }
            return "\(label)elevation loss \(formatVoiceElevation(stats.elevationLoss))"
        case .calories:
            guard stats.calories > 0 else { return nil }
            return "\(label)\(Int(stats.calories)) calories"
        default:
            // Unsupported metrics (.grade, .powerEstimate, etc.) silently skip.
            // The settings picker filters these out so users don't pick them
            // expecting a readout — but old saved configs may still have them.
            return nil
        }
    }

    /// Voice-formatted duration. Includes hours once the value is at least
    /// one hour (rider was getting "92 minutes" before for long rides).
    private func formatVoiceDuration(_ seconds: TimeInterval) -> String {
        let total = max(0, Int(seconds))
        let hours = total / 3600
        let mins = (total % 3600) / 60
        let secs = total % 60

        if hours > 0 {
            // Drop seconds at the hour scale — "1 hour 32 minutes" reads
            // cleanly; "1 hour 32 minutes 17 seconds" is just noise.
            if mins == 0 {
                return "\(hours) hour\(hours == 1 ? "" : "s")"
            }
            return "\(hours) hour\(hours == 1 ? "" : "s") \(mins) minute\(mins == 1 ? "" : "s")"
        }
        if mins == 0 {
            return "\(secs) second\(secs == 1 ? "" : "s")"
        } else if secs == 0 {
            return "\(mins) minute\(mins == 1 ? "" : "s")"
        }
        return "\(mins) minute\(mins == 1 ? "" : "s") \(secs) seconds"
    }

    private func formatVoiceSpeed(_ mps: Double) -> String {
        if currentUnits.speed == .mph {
            return String(format: "%.1f miles per hour", mps * 2.23694)
        } else {
            return String(format: "%.1f kilometers per hour", mps * 3.6)
        }
    }

    private func formatVoiceElevation(_ meters: Double) -> String {
        if currentUnits.elevation == .feet {
            let feet = Int((meters * 3.28084).rounded())
            return "\(feet) feet"
        } else {
            let m = Int(meters.rounded())
            return "\(m) meter\(m == 1 ? "" : "s")"
        }
    }

    // MARK: - Queue Processing

    private func enqueueAlert(_ alert: VoiceAlert) {
        alertQueue.enqueue(alert)
        processQueue()
    }

    private func processQueue() {
        guard !isProcessingAlert, !isStopped else { return }

        // Respect cooldown for stat-level alerts only; higher-priority alerts always proceed
        if let next = alertQueue.peekNext(), next.priority == .stat, !canSpeak {
            let wait = cooldown - Date().timeIntervalSince(lastAnnouncementTime)
            let item = DispatchWorkItem { [weak self] in self?.processQueue() }
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.1, wait), execute: item)
            pendingWorkItem = item
            return
        }

        guard let alert = alertQueue.dequeueNext() else { return }

        // Relevance gate — drop stale alerts (e.g. a turn-approach for a turn
        // we've already passed, or an off-route alert when we're back on route).
        if let check = alert.relevanceCheck, !check() {
            // Skip silently and try the next alert in the same processing tick.
            processQueue()
            return
        }

        isProcessingAlert = true
        audioSpeak(alert.text, mode: alert.mode, category: alert.category, priority: alert.priority)
    }

    fileprivate func finishCurrentAlert() {
        isProcessingAlert = false
        if alertQueue.isEmpty {
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            return
        }
        let item = DispatchWorkItem { [weak self] in self?.processQueue() }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
        pendingWorkItem = item
    }

    // MARK: - Audio Routing

    private func audioSpeak(_ text: String, mode: AlertMode, category: String?, priority: AlertPriority) {
        guard isEnabled, !isStopped else {
            finishCurrentAlert()
            return
        }

        lastAnnouncementTime = Date()

        if mode.includesHaptic {
            onHaptic?(mode)
        }

        if workoutManager?.ridePreferences.wakeOnAlert == true {
            scheduleWakeNotification(body: text)
        }

        guard mode.includesVoice else {
            finishCurrentAlert()
            return
        }

        switch resolveAudioRoute() {
        case .watchLocal:
            speakLocally(text)

        case .phoneMirror:
            // Build the wire payload and hand it to VoiceAlertTransport.
            // The transport handles the race-and-fallback: phone if
            // reachable AND acks didStart within 800ms, else local TTS.
            let payload = AlertPayload(
                kind: alertKind(for: category, priority: priority),
                priority: alertTransportPriority(for: priority),
                text: text,
                ttl: 15
            )
            inFlightAlertID = payload.id
            VoiceAlertTransport.shared.deliver(payload) { [weak self] outcome in
                guard let self, !self.isStopped else { return }
                // Stale completion (e.g. ride reset between deliver and
                // outcome) — drop silently to avoid double-advance.
                guard self.inFlightAlertID == payload.id else { return }
                self.inFlightAlertID = nil
                switch outcome {
                case .phoneSpoke:
                    // Phone is speaking — advance the watch queue
                    // immediately. AVSpeechSynthesizer on the phone owns
                    // ordering of any subsequent utterances we send while
                    // it's still mid-stream.
                    self.finishCurrentAlert()
                case .localFallback(let fallbackText, _):
                    // Phone path failed. Speak on watch; speechSynthesizer
                    // didFinish will call finishCurrentAlert.
                    self.speakLocally(fallbackText)
                }
            }
        }
    }

    private func clearInFlight() {
        inFlightAlertID = nil
    }

    /// Map a watch-internal AlertPriority + category string to the
    /// AlertPayload's wire schema. The wire schema's `kind` is what the
    /// phone uses for things like notification routing and telemetry; the
    /// watch's priority enum is queue-arbitration state that doesn't
    /// cross the link.
    private func alertKind(for category: String?, priority: AlertPriority) -> AlertKind {
        switch category {
        case "atTurn":         return .turnImmediate
        case "turnApproach":   return .turnApproach
        case "offRoute":       return .offRoute
        case "backOnRoute":    return .backOnRoute
        case "arrival":        return .arrival
        case "halfway":        return .halfway
        case "lap":            return .split
        case "autoPause", "autoResume": return .autoPause
        case "waypoint":       return .waypoint
        default:
            // Fall back from priority when category is nil (e.g. "Last
            // turn complete. 200m to finish." doesn't carry a category).
            switch priority {
            case .immediateTurn: return .turnImmediate
            case .turnApproach:  return .turnApproach
            case .navEvent:      return .lastTurn
            case .autoPause:     return .autoPause
            case .stat:          return .info
            }
        }
    }

    /// Map watch queue priority → transport priority.
    /// Stat readouts go .soon (transferUserInfo) so they don't churn the
    /// sendMessage queue during a split announcement. Everything else is
    /// .immediate (sendMessage + 800ms race).
    private func alertTransportPriority(for priority: AlertPriority) -> AlertTransportPriority {
        switch priority {
        case .immediateTurn, .navEvent, .turnApproach, .autoPause:
            return .immediate
        case .stat:
            return .soon
        }
    }

    /// Result of routing decision — either keep speech on the watch or send
    /// it via the transport.
    private enum AudioRoute {
        case watchLocal
        case phoneMirror
    }

    /// Decide where to play this alert. Phone-vs-watch decision lives here;
    /// the transport handles the "phone path actually worked or not"
    /// question on top.
    ///
    /// Order:
    ///   1. User override pins to .watch → always local.
    ///   2. Auto + watch BT/headphones connected → local (audio goes to
    ///      headphones rather than dropping to phone).
    ///   3. Otherwise hand to transport (it will either get a didStart ack
    ///      from the phone or fall back to local on timeout).
    private func resolveAudioRoute() -> AudioRoute {
        let override = preferences.audioOutput.source
        if override == .watch { return .watchLocal }
        if override == .auto, isWatchUsingExternalAudioOutput() { return .watchLocal }
        return .phoneMirror
    }

    /// True when the watch's current audio route includes BT or wired
    /// headphones (i.e. *not* just the built-in speaker). When this is true,
    /// playing locally on the watch routes through the headphones — usually
    /// what the rider wants over going through the phone.
    private func isWatchUsingExternalAudioOutput() -> Bool {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        return outputs.contains { output in
            switch output.portType {
            case .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .headphones, .airPlay:
                return true
            default:
                return false
            }
        }
    }

    private func scheduleWakeNotification(body: String) {
        let content = UNMutableNotificationContent()
        content.body = body
        content.interruptionLevel = .timeSensitive
        let request = UNNotificationRequest(
            identifier: "nav-wake-alert",
            content: content,
            trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    private func speakLocally(_ text: String) {
        guard !isStopped else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("VoiceNavigator activate error: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = PreferredVoice.resolved
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        synthesizer.speak(utterance)
    }
}

extension TurnDirection {
    var voiceLabel: String {
        switch self {
        case .left:        return "turn left"
        case .slightLeft:  return "slight left"
        case .sharpLeft:   return "sharp left"
        case .right:       return "turn right"
        case .slightRight: return "slight right"
        case .sharpRight:  return "sharp right"
        case .uTurn:       return "make a U-turn"
        case .straight:    return "continue straight"
        }
    }

    var voiceLabel2: String {
        switch self {
        case .left:        return "left turn"
        case .slightLeft:  return "slight left"
        case .sharpLeft:   return "sharp left turn"
        case .right:       return "right turn"
        case .slightRight: return "slight right"
        case .sharpRight:  return "sharp right turn"
        case .uTurn:       return "U-turn"
        case .straight:    return "straight"
        }
    }
}

extension VoiceNavigator: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        guard !synthesizer.isSpeaking else { return }
        finishCurrentAlert()
    }
}
