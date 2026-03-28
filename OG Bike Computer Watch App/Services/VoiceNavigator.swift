//
//  VoiceNavigator.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/5/26.
//

import AVFoundation
import CoreLocation
import Combine

class VoiceNavigator: NSObject, ObservableObject {
    static let shared = VoiceNavigator()

    @Published var isEnabled = true

    var preferences: NavigationAlertPreferences = .default

    private var alertDistances: [Double] {
        preferences.turnAlerts.alertDistances
    }
    private let groupTurnThreshold: Double = 150 // meters between turns to group them

    private let atTurnThreshold: Double = 20
    private let cooldown: TimeInterval = 6
    private let minTimeBeforeTurn: TimeInterval = 4

    // State
    private var isActivelyMoving = true
    private var currentTurnIndex: Int?
    private var firedTurnAlerts: Set<Int> = []
    private var groupedApproachTurnIndices: Set<Int> = []

    private var trackingFinish = false
    private var firedFinishAlerts: Set<Int> = []

    private var announcedHalfway = false
    private var announcedArrival = false
    private var announcedOffRoute = false
    private var wasOffRoute = false
    private var lastAnnouncementTime: Date = .distantPast

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
        announcedArrival = false
        announcedOffRoute = false
        wasOffRoute = false
        lastAnnouncementTime = .distantPast
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
        announcedArrival = false
        announcedOffRoute = false
        wasOffRoute = false
        lastAnnouncementTime = .distantPast
    }

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Same options as PhoneSpeechPlayer — duckOthers is required for
            // background activation (implicitly sets mixWithOthers).
            // interruptSpokenAudioAndMixWithOthers pauses podcasts.
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
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
                speak("You have arrived. Route complete.", mode: navEvents.arrivalAlert)
            }
            return
        }

        if nav.isOffRoute {
            if !announcedOffRoute {
                announcedOffRoute = true
                let rejoinDirection = voiceDirectionToTarget(heading: heading, bearingToTarget: nav.bearingToRoute)
                if let missed = nav.missedTurn {
                    speak("Off route. Missed \(missed.direction.voiceLabel2). \(rejoinDirection.capitalized) to rejoin.", mode: navEvents.offRouteAlert)
                } else {
                    speak("Off route. \(rejoinDirection.capitalized) to rejoin.", mode: navEvents.offRouteAlert)
                }
            }
            wasOffRoute = true
            return
        } else if wasOffRoute {
            wasOffRoute = false
            announcedOffRoute = false
            speak("Back on route.", mode: navEvents.backOnRouteAlert)
            if let turn = nav.nextTurn {
                let dist = nav.distanceToNextTurn
                let turnText = voiceText(for: turn)
                let turnMode = preferences.turnAlerts.resolvedPrimaryApproachMode()
                let item = DispatchWorkItem { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.speak("in \(formatVoiceDistance(dist)), \(turnText).", mode: turnMode)
                }
                pendingWorkItem?.cancel()
                pendingWorkItem = item
                DispatchQueue.main.asyncAfter(deadline: .now() + 2, execute: item)
            }
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

        if !announcedHalfway {
            let half = route.totalDistance / 2
            if nav.distanceAlongRoute >= half {
                announcedHalfway = true
                if isActivelyMoving, canSpeak {
                    speak("Halfway point. \(formatVoiceDistance(nav.distanceRemaining)) to go.", mode: navEvents.halfwayAlert)
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
        if lower.hasPrefix("make a ") {
            return String(desc.dropFirst(7)).lowercased()
        }

        // Use the description directly — it reads naturally
        // "Turn left", "Turn right onto X", "Keep right onto X"
        return desc.lowercased()
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
            if !isAtTurn && !isActivelyMoving {
                fired.insert(i)
                continue
            }

            // Suppress approach prompts for turns already grouped
            // with a prior turn's announcement (at-turn still fires)
            if !isAtTurn && suppressApproach {
                fired.insert(i)
                continue
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
            speak(isAtTurn ? atZeroText : approachText(distance), mode: mode)
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

    private func speak(_ text: String, mode: AlertMode = .voiceAndHaptic) {
        guard !isStopped else { return }

        lastAnnouncementTime = Date()

        if mode.includesHaptic {
            onHaptic?(mode)
        }

        guard mode.includesVoice else { return }

        if let wm = workoutManager {
            wm.sendSpeechToPhone(text) { [weak self] spoken in
                guard let self, !self.isStopped else { return }
                if !spoken {
                    self.speakLocally(text)
                }
            }
        } else {
            speakLocally(text)
        }
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

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceNavigator deactivate error: \(error)")
        }
    }
}
