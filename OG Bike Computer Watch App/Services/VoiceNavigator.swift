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

    private let alertDistances: [Double] = [
        402.336,  // ¼ mile
        60.96,    // 200 feet
        0         // at the turn
    ]
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

    func update(nav: NavigationTracker, speed: Double, isActivelyMoving: Bool = true) {
        guard isEnabled, !isStopped else { return }
        guard let route = nav.processedRoute else { return }

        self.isActivelyMoving = isActivelyMoving

        if nav.isRouteComplete {
            if !announcedArrival {
                announcedArrival = true
                speak("You have arrived. Route complete.")
            }
            return
        }

        if nav.isOffRoute {
            if !announcedOffRoute {
                announcedOffRoute = true
                if let missed = nav.missedTurn {
                    speak("Off route. Missed \(missed.direction.voiceLabel2).")
                } else {
                    speak("Off route.")
                }
            }
            wasOffRoute = true
            return
        } else if wasOffRoute {
            wasOffRoute = false
            announcedOffRoute = false
            speak("Back on route.")
            if let turn = nav.nextTurn {
                let dist = nav.distanceToNextTurn
                let item = DispatchWorkItem { [weak self] in
                    guard let self, !self.isStopped else { return }
                    self.speak("in \(self.formatVoiceDistance(dist)), \(turn.direction.voiceLabel).")
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
                    let followingTurn = nav.processedRoute
                        .flatMap { nearbyFollowingTurn(after: turn, in: $0) }

                    if let ft = followingTurn {
                        groupedApproachTurnIndices.insert(ft.index)
                        speak("in \(formatVoiceDistance(dist)), \(turn.direction.voiceLabel) then \(ft.direction.voiceLabel).")
                    } else {
                        speak("in \(formatVoiceDistance(dist)), \(turn.direction.voiceLabel).")
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
            let followingTurn = nav.processedRoute
                .flatMap { nearbyFollowingTurn(after: turn, in: $0) }

            if fireDistanceAlert(
                distance: nav.distanceToNextTurn,
                speed: speed,
                fired: &firedTurnAlerts,
                suppressApproach: approachSuppressed,
                atZeroText: "\(turn.direction.voiceLabel.localizedCapitalized).",
                approachText: { d in
                    if let ft = followingTurn {
                        // "In 200 feet, turn right then left."
                        self.groupedApproachTurnIndices.insert(ft.index)
                        return "in \(self.formatVoiceDistance(d)), \(turn.direction.voiceLabel) then \(ft.direction.voiceLabel)."
                    }
                    return "in \(self.formatVoiceDistance(d)), \(turn.direction.voiceLabel)."
                }
            ) { return }

            let isLastTurn = route.turnPoints.last?.index == turn.index
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
                approachText: { d in "Finish \(self.formatVoiceDistance(d))." }
            ) { return }
        }

        if !announcedHalfway {
            let half = route.totalDistance / 2
            if nav.distanceAlongRoute >= half {
                announcedHalfway = true
                if isActivelyMoving, canSpeak {
                    speak("Halfway point. \(formatVoiceDistance(nav.distanceRemaining)) to go.")
                }
                return
            }
        }
    }
    
    // Returns the turn immediately after `turn` if it's within
    // groupTurnThreshold meters, otherwise nil.
    private func nearbyFollowingTurn(
        after turn: TurnPoint,
        in route: ProcessedRoute
    ) -> TurnPoint? {
        guard let idx = route.turnPoints.firstIndex(where: { $0.index == turn.index }),
              idx + 1 < route.turnPoints.count else { return nil }
        let next = route.turnPoints[idx + 1]
        let gap = next.distanceFromStart - turn.distanceFromStart
        return gap <= groupTurnThreshold ? next : nil
    }

    
    private func fireDistanceAlert(
        distance: Double,
        speed: Double,
        fired: inout Set<Int>,
        suppressApproach: Bool = false,
        atZeroText: String,
        approachText: (Double) -> String
    ) -> Bool {
        for (i, alertDist) in alertDistances.enumerated() {
            guard !fired.contains(i) else { continue }

            let isAtTurn = alertDist == 0
            let threshold = isAtTurn ? atTurnThreshold : alertDist
            guard distance <= threshold else { continue }

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
            speak(isAtTurn ? atZeroText : approachText(distance))
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

    private func speak(_ text: String) {
        guard !isStopped else { return }

        lastAnnouncementTime = Date()

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

    private func formatVoiceDistance(_ meters: Double) -> String {
        let feet = meters * 3.28084
        let miles = meters / 1609.344

        if feet < 150 {
            let rounded = max(50, Int((feet / 50).rounded()) * 50)
            return "\(rounded) feet"
        }
        if feet < 300 {
            let hundreds = Int((feet / 100).rounded())
            return "\(hundreds) hundred feet"
        }
        if miles < 0.2 {
            let rounded = Int((feet / 100).rounded()) * 100
            return "\(rounded) feet"
        }
        if miles < 0.3 { return "a quarter mile" }
        if miles < 0.6 { return "half a mile" }
        if miles < 0.85 { return "three quarters of a mile" }
        if miles < 1.1 { return "1 mile" }
        if miles < 1.3 { return "about a mile" }
        if miles < 1.7 { return "a mile and a half" }
        if miles < 2.2 { return "2 miles" }
        let rounded = Int(miles.rounded())
        return "\(rounded) miles"
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
