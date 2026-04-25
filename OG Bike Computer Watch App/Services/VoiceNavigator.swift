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
    private var pendingHalfway = false  // deferred when canSpeak is false
    private var announcedArrival = false
    private var announcedOffRoute = false

    private var wasOffRoute = false
    private var lastAnnouncementTime: Date = .distantPast
    private var lastTurnAlertTime: Date = .distantPast  // for minimum gap enforcement

    // Prevents any speech after stop
    private var isStopped = false
    private var pendingWorkItem: DispatchWorkItem?

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
        pendingHalfway = false
        announcedArrival = false
        announcedOffRoute = false

        wasOffRoute = false
        lastAnnouncementTime = .distantPast
        lastTurnAlertTime = .distantPast
        statQueue.removeAll()
        statQueueIndex = 0
        isStatAnnouncing = false
        statInterruptedAtIndex = nil
        statResumeWorkItem?.cancel()
        statResumeWorkItem = nil
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
        pendingHalfway = false
        announcedArrival = false
        announcedOffRoute = false

        wasOffRoute = false
        lastAnnouncementTime = .distantPast
        lastTurnAlertTime = .distantPast
    }

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Same options as PhoneSpeechPlayer — duckOthers is required for
            // background activation (implicitly sets mixWithOthers).
            // interruptSpokenAudioAndMixWithOthers pauses podcasts.
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetooth, .allowBluetoothA2DP])
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
                speak("You have arrived. Route complete.", mode: navEvents.arrivalAlert, category: "arrival")
            }
            return
        }

        if nav.isOffRoute {
            if !announcedOffRoute {
                announcedOffRoute = true
                if let missed = nav.missedTurn {
                    speak("Off route. Missed \(missed.direction.voiceLabel2).", mode: navEvents.offRouteAlert, category: "offRoute")
                } else {
                    speak("Off route.", mode: navEvents.offRouteAlert, category: "offRoute")
                }
            }
            wasOffRoute = true
            return
        } else if wasOffRoute {
            wasOffRoute = false
            announcedOffRoute = false
    
            // Calculate direction to continue along route after rejoining
            let routeBearing = nav.currentBearing
            let continueDirection = voiceDirectionToTarget(heading: heading, bearingToTarget: routeBearing)
            speak("Back on route. \(continueDirection.capitalized) to continue.", mode: navEvents.backOnRouteAlert, category: "backOnRoute")
            return
        }

        if let turn = nav.nextTurn, turn.index != currentTurnIndex {
            let passedTurn = currentTurnIndex != nil
            currentTurnIndex = turn.index
            firedTurnAlerts.removeAll()
            groupedApproachTurnIndices.remove(turn.index)
            trackingFinish = false
            firedFinishAlerts.removeAll()

            if passedTurn {
                if isActivelyMoving {
                    let dist = nav.distanceToNextTurn
                    let followingTurn = nav.nearbyFollowingTurn(after: turn)

                    if let ft = followingTurn {
                        groupedApproachTurnIndices.insert(ft.index)
                        speak("in \(formatVoiceDistance(dist)), \(voiceText(for: turn)) then \(ft.direction.voiceLabel).")
                    } else {
                        speak("in \(formatVoiceDistance(dist)), \(voiceText(for: turn)).")
                    }
                    // Record time of this "next turn" announcement for gap enforcement
                    lastTurnAlertTime = Date()
                    markPassedThresholds(distance: dist, into: &firedTurnAlerts)
                }
                return
            }
        }

        if let turn = nav.nextTurn {
            // Check if this turn's approach was already covered
            // as part of a grouped announcement from the previous turn
            let approachSuppressed = groupedApproachTurnIndices.contains(turn.index)

            // Build approach text — include following turn if nearby
            let followingTurn = nav.nearbyFollowingTurn(after: turn)

            if fireDistanceAlert(
                distance: nav.distanceToNextTurn,
                speed: speed,
                fired: &firedTurnAlerts,
                suppressApproach: approachSuppressed,
                atZeroText: "\(self.voiceText(for: turn).localizedCapitalized).",
                approachText: { d in
                    if let ft = followingTurn {
                        // "In 200 feet, turn right onto Main St then left."
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
                        speak("Last turn complete. \(formatVoiceDistance(remaining)) to finish.")
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
                    speak("Last turn complete. \(formatVoiceDistance(remaining)) to finish.")
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

        // Check for pending halfway announcement (deferred from earlier when canSpeak was false)
        if pendingHalfway, canSpeak, isActivelyMoving {
            pendingHalfway = false
            announceHalfway(distanceRemaining: nav.distanceRemaining, mode: navEvents.halfwayAlert)
            return
        }

        if !announcedHalfway {
            let half = route.totalDistance / 2
            if nav.distanceAlongRoute >= half {
                announcedHalfway = true
                if isActivelyMoving, canSpeak {
                    announceHalfway(distanceRemaining: nav.distanceRemaining, mode: navEvents.halfwayAlert)
                } else if isActivelyMoving {
                    // Cooldown active — defer to next update cycle
                    pendingHalfway = true
                }
                return
            }
        }
    }

    /// Build voice text for a turn, including street name from description when available.
    /// Uses the description's own phrasing when possible (e.g. "Keep right onto Navy Pier Flyover")
    /// so that turns like "keep right" aren't awkwardly converted to "slight right".
    private func voiceText(for turn: TurnPoint) -> String {
        guard let desc = turn.description, !desc.isEmpty else {
            return turn.direction.voiceLabel
        }

        // Use the full description as the voice cue — it's already human-readable
        // e.g. "Turn right onto West School Street", "Keep left onto Lakewood Ave"
        let lower = desc.lowercased()

        // Strip leading "Make a " prefix (e.g. "Make a U-turn onto ...")
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

            // Skip if mode is none
            if mode == .none {
                fired.insert(i)
                continue
            }

            // Suppress approach prompts when not actively moving
            // Don't mark as fired — retry when rider starts moving again
            if !isAtTurn && !isActivelyMoving {
                continue
            }

            // Suppress approach prompts for turns already grouped
            // with a prior turn's announcement (at-turn still fires)
            if !isAtTurn && suppressApproach {
                fired.insert(i)
                continue
            }

            // Minimum time gap: skip approach alerts if too soon after the
            // auto "next turn" announcement. Never skip at-turn alerts.
            // Bypass gap enforcement within 200m of the turn to ensure final approach alerts fire.
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
            let cat = isTurnAlert ? (isAtTurn ? "atTurn" : "turnApproach") : nil
            speak(isAtTurn ? atZeroText : approachText(distance), mode: mode, category: cat)
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
        speak("Auto paused.", mode: mode, category: "autoPause")
    }

    func announceAutoResume(mode: AlertMode) {
        speak("Resumed.", mode: mode, category: "autoResume")
    }

    // MARK: - Split / Halfway Stat Queue

    private var statQueue: [String] = []
    private var statQueueIndex: Int = 0
    private var isStatAnnouncing: Bool = false
    private var statInterruptedAtIndex: Int?
    private var statResumeWorkItem: DispatchWorkItem?
    private var statMode: AlertMode = .voiceAndHaptic

    func announceSplit(number: Int, splitDistance: Double, splitStats: SplitStats, rideStats: SplitStats, metrics: [SplitMetricConfig], mode: AlertMode) {
        // Order metrics so .distance is always first if present
        let orderedMetrics = metrics.sorted { a, _ in a.metric == .distance }

        var parts: [String] = []
        for config in orderedMetrics {
            let splitVal = statText(for: config.metric, from: splitStats, label: "")
            let rideVal = statText(for: config.metric, from: rideStats, label: "")

            switch config.scope {
            case .split:
                if let sv = splitVal { parts.append(sv) }
            case .ride:
                if let rv = rideVal { parts.append("ride \(rv)") }
            case .both:
                if let sv = splitVal { parts.append(sv) }
                if let rv = rideVal { parts.append("ride \(rv)") }
            }
        }

        // Build queue: header first, then each stat as a separate utterance
        let header = "\(formatVoiceDistance(splitDistance)) split \(number)."
        startStatQueue(header: header, parts: parts, mode: mode)
    }

    private func startStatQueue(header: String?, parts: [String], mode: AlertMode) {
        // Cancel any in-progress stat announcement
        statResumeWorkItem?.cancel()
        statResumeWorkItem = nil
        statInterruptedAtIndex = nil

        statQueue = []
        if let header { statQueue.append(header) }
        statQueue.append(contentsOf: parts)
        statQueueIndex = 0
        statMode = mode
        isStatAnnouncing = true
        speakNextStat()
    }

    private func speakNextStat() {
        guard isStatAnnouncing, statQueueIndex < statQueue.count, !isStopped else {
            isStatAnnouncing = false
            return
        }
        speak(statQueue[statQueueIndex], mode: statMode, category: "lap")
    }

    /// Called by the speech delegate when a stat utterance finishes.
    /// Advances to the next stat with a brief pause.
    fileprivate func advanceStatQueue() {
        statQueueIndex += 1
        if statQueueIndex < statQueue.count {
            let item = DispatchWorkItem { [weak self] in
                self?.speakNextStat()
            }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.2, execute: item)
            statResumeWorkItem = item
        } else {
            isStatAnnouncing = false
        }
    }

    /// Interrupts the stat queue (e.g. for a turn alert). Call before speaking the interrupting alert.
    fileprivate func interruptStatQueue() {
        guard isStatAnnouncing else { return }
        statInterruptedAtIndex = statQueueIndex
        isStatAnnouncing = false
        statResumeWorkItem?.cancel()
        statResumeWorkItem = nil
    }

    private func announceHalfway(distanceRemaining: Double, mode: AlertMode) {
        let header = "Halfway point. \(formatVoiceDistance(distanceRemaining)) to go."

        // If split stats are enabled, queue the halfway header + ride stats together
        if let wm = workoutManager {
            let splitPrefs = preferences.splitAlerts
            if splitPrefs.enabled, !splitPrefs.metrics.isEmpty {
                let rideStats = wm.currentRideStats()
                let orderedMetrics = splitPrefs.metrics.sorted { a, _ in a.metric == .distance }
                var parts: [String] = []
                for config in orderedMetrics {
                    if let rv = statText(for: config.metric, from: rideStats, label: "") {
                        parts.append(rv)
                    }
                }
                if !parts.isEmpty {
                    startStatQueue(header: header, parts: parts, mode: mode)
                    return
                }
            }
        }

        // No stats to read — just speak the header
        speak(header, mode: mode, category: "halfway")
    }

    /// Schedules resume of the stat queue after an interruption.
    /// Restarts from the stat that was interrupted.
    fileprivate func scheduleStatResume() {
        guard let resumeIdx = statInterruptedAtIndex else { return }
        statInterruptedAtIndex = nil

        let item = DispatchWorkItem { [weak self] in
            guard let self, !self.isStopped else { return }
            self.statQueueIndex = resumeIdx // re-read interrupted stat
            self.isStatAnnouncing = true
            self.speakNextStat()
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: item)
        statResumeWorkItem = item
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

    private func speak(_ text: String, mode: AlertMode = .voiceAndHaptic, category: String? = nil) {
        guard isEnabled, !isStopped else { return }

        // Interrupt stat queue for non-stat alerts (e.g. turn alerts)
        if category != "lap" && isStatAnnouncing {
            interruptStatQueue()
        }

        lastAnnouncementTime = Date()

        if mode.includesHaptic {
            onHaptic?(mode)
        }

        if workoutManager?.ridePreferences.wakeOnAlert == true {
            scheduleWakeNotification(body: text)
        }

        guard mode.includesVoice else {
            // Even without voice, advance stat queue if this was a stat utterance
            if category == "lap" && isStatAnnouncing {
                advanceStatQueue()
            }
            return
        }

        if let wm = workoutManager {
            wm.sendSpeechToPhone(text, category: category) { [weak self] spoken in
                guard let self, !self.isStopped else { return }
                if !spoken {
                    self.speakLocally(text)
                } else if self.isStatAnnouncing {
                    // Phone handled speech — estimate duration and advance queue
                    // (~80ms per character is a rough TTS estimate at 1.1x rate)
                    let estimatedDuration = max(1.0, Double(text.count) * 0.06)
                    DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                        guard self.isStatAnnouncing else { return }
                        self.advanceStatQueue()
                    }
                } else if self.statInterruptedAtIndex != nil {
                    // Non-stat speech routed to phone, schedule stat resume
                    let estimatedDuration = max(1.0, Double(text.count) * 0.06)
                    DispatchQueue.main.asyncAfter(deadline: .now() + estimatedDuration) {
                        self.scheduleStatResume()
                    }
                }
            }
        } else {
            speakLocally(text)
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
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        synthesizer.stopSpeaking(at: .word)
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
        // Don't deactivate if we interrupted one utterance to start another
        guard !synthesizer.isSpeaking else { return }

        // Advance stat queue if we're in the middle of a split/halfway readout
        if isStatAnnouncing {
            advanceStatQueue()
            return
        }

        // If a stat queue was interrupted, schedule resume after idle
        if statInterruptedAtIndex != nil {
            scheduleStatResume()
            return
        }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceNavigator deactivate error: \(error)")
        }
    }
}
