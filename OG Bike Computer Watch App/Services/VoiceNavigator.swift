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

    private var wasOffRoute = false
    private var lastAnnouncementTime: Date = .distantPast
    private var lastTurnAlertTime: Date = .distantPast

    // Prevents any speech after stop
    private var isStopped = false
    private var pendingWorkItem: DispatchWorkItem?

    // Alert queue
    private let alertQueue = VoiceAlertQueue()
    private var isProcessingAlert = false

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

        wasOffRoute = false
        lastAnnouncementTime = .distantPast
        lastTurnAlertTime = .distantPast

        alertQueue.cancelAll()
        isProcessingAlert = false

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
                    mutualCancelKey: "route-state"
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
            enqueueAlert(VoiceAlert(
                priority: .navEvent,
                text: "Back on route. \(continueDirection.capitalized) to continue.",
                mode: navEvents.backOnRouteAlert,
                category: "backOnRoute",
                alertKey: "route-state",
                mutualCancelKey: "route-state"
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
            groupedApproachTurnIndices.remove(turn.index)
            trackingFinish = false
            firedFinishAlerts.removeAll()

            if passedTurn {
                if isActivelyMoving {
                    let dist = nav.distanceToNextTurn
                    let followingTurn = nav.nearbyFollowingTurn(after: turn)

                    let text: String
                    if let ft = followingTurn {
                        groupedApproachTurnIndices.insert(ft.index)
                        text = "in \(formatVoiceDistance(dist)), \(voiceText(for: turn)) then \(ft.direction.voiceLabel)."
                    } else {
                        text = "in \(formatVoiceDistance(dist)), \(voiceText(for: turn))."
                    }
                    enqueueAlert(VoiceAlert(
                        priority: .turnApproach,
                        text: text,
                        mode: preferences.turnAlerts.mode(forAlertIndex: 0, totalCount: alertDistances.count),
                        category: "turnApproach",
                        alertKey: "turn-approach-\(turn.index)"
                    ))
                    lastTurnAlertTime = Date()
                    markPassedThresholds(distance: dist, into: &firedTurnAlerts)
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
                atZeroText: "\(self.voiceText(for: turn).localizedCapitalized).",
                approachText: { d in
                    if let ft = followingTurn {
                        self.groupedApproachTurnIndices.insert(ft.index)
                        return "in \(formatVoiceDistance(d)), \(self.voiceText(for: turn)) then \(ft.direction.voiceLabel)."
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
    }

    private func voiceText(for turn: TurnPoint) -> String {
        guard let desc = turn.description, !desc.isEmpty else {
            return turn.direction.voiceLabel
        }

        let lower = desc.lowercased()

        var baseText: String
        if lower.hasPrefix("make a ") {
            baseText = String(desc.dropFirst(7)).lowercased()
        } else {
            baseText = desc.lowercased()
        }

        return baseText
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
                        replacesKey: "turn-approach-\(idx)"
                    ))
                } else {
                    enqueueAlert(VoiceAlert(
                        priority: .turnApproach,
                        text: text,
                        mode: mode,
                        category: cat,
                        alertKey: "turn-approach-\(idx)"
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
        let orderedMetrics = metrics.sorted { a, _ in a.metric == .distance }

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

    private func announceHalfway(distanceRemaining: Double, mode: AlertMode) {
        let header = "Halfway point. \(formatVoiceDistance(distanceRemaining)) to go."
        enqueueAlert(VoiceAlert(priority: .stat, text: header, mode: mode, category: "halfway"))

        if let wm = workoutManager {
            let splitPrefs = preferences.splitAlerts
            if splitPrefs.enabled, !splitPrefs.metrics.isEmpty {
                let rideStats = wm.currentRideStats()
                let orderedMetrics = splitPrefs.metrics.sorted { a, _ in a.metric == .distance }
                for config in orderedMetrics {
                    if let rv = statText(for: config.metric, from: rideStats, label: "") {
                        enqueueAlert(VoiceAlert(priority: .stat, text: rv, mode: mode, category: "halfway"))
                    }
                }
            }
        }
    }

    private func statText(for metric: MetricType, from stats: SplitStats, label: String) -> String? {
        switch metric {
        case .movingTime:
            return "\(label)time \(formatVoiceDuration(stats.movingTime))"
        case .averageSpeed:
            return "\(label)average speed \(formatVoiceSpeed(stats.averageSpeed))"
        case .maxSpeed:
            guard stats.maxSpeed > 0 else { return nil }
            return "\(label)max speed \(formatVoiceSpeed(stats.maxSpeed))"
        case .distance:
            return "\(label)distance \(formatVoiceDistance(stats.distance))"
        case .heartRate:
            guard stats.averageHeartRate > 0 else { return nil }
            return "\(label)average heart rate \(Int(stats.averageHeartRate))"
        default:
            return nil
        }
    }

    private func formatVoiceDuration(_ seconds: TimeInterval) -> String {
        let mins = Int(seconds) / 60
        let secs = Int(seconds) % 60
        if mins == 0 {
            return "\(secs) seconds"
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
        isProcessingAlert = true
        audioSpeak(alert.text, mode: alert.mode, category: alert.category)
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

    private func audioSpeak(_ text: String, mode: AlertMode, category: String?) {
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

        if let wm = workoutManager {
            wm.sendSpeechToPhone(text, category: category) { [weak self] spoken in
                guard let self, !self.isStopped else { return }
                if !spoken {
                    self.speakLocally(text)
                } else {
                    DispatchQueue.main.asyncAfter(deadline: .now() + Self.estimatedSpeechDuration(for: text)) {
                        self.finishCurrentAlert()
                    }
                }
            }
        } else {
            speakLocally(text)
        }
    }

    /// Estimate how long it takes to speak `text` at our utterance rate.
    /// Digits expand ~5× when spoken ("145" → "one hundred forty five"), so they're
    /// counted as 5 spoken characters each. Underestimating causes the queue to
    /// dispatch the next alert before the phone finishes the current one.
    private static func estimatedSpeechDuration(for text: String) -> TimeInterval {
        let digitCount = text.filter { $0.isNumber }.count
        let spokenCharCount = text.count + digitCount * 4
        return max(1.5, Double(spokenCharCount) * 0.08)
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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
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
