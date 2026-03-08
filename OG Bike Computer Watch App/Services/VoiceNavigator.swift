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
        30.48,    // 100 feet
        0         // at the turn
    ]

    private let atTurnThreshold: Double = 20
    private let cooldown: TimeInterval = 6
    private let minTimeBeforeTurn: TimeInterval = 4

    // State
    private var currentTurnIndex: Int?
    private var firedTurnAlerts: Set<Int> = []

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

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            // Same options as PhoneSpeechPlayer — duckOthers is required for
            // background activation (implicitly sets mixWithOthers).
            // interruptSpokenAudioAndMixWithOthers pauses podcasts.
            try session.setCategory(.playback, mode: .voicePrompt, options: [.mixWithOthers, .duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("VoiceNavigator audio session config error: \(error)")
        }
        // Must come AFTER reset()
        isStopped = false
    }

    func update(nav: NavigationTracker, speed: Double) {
        guard isEnabled, !isStopped else { return }
        guard let route = nav.processedRoute else { return }

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
                    self.speak("\(self.formatVoiceDistance(dist)), \(turn.direction.voiceLabel).")
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
            trackingFinish = false
            firedFinishAlerts.removeAll()

            if passedTurn {
                let dist = nav.distanceToNextTurn
                speak("\(formatVoiceDistance(dist)), \(turn.direction.voiceLabel).")
                markPassedThresholds(distance: dist, into: &firedTurnAlerts)
                return
            }
        }

        if let turn = nav.nextTurn {
            if fireDistanceAlert(
                distance: nav.distanceToNextTurn,
                speed: speed,
                fired: &firedTurnAlerts,
                atZeroText: "\(turn.direction.voiceLabel.localizedCapitalized).",
                approachText: { d in "\(self.formatVoiceDistance(d)), \(turn.direction.voiceLabel)." }
            ) { return }

            let isLastTurn = route.turnPoints.last?.index == turn.index
            if isLastTurn, firedTurnAlerts.contains(alertDistances.count - 1) {
                if !trackingFinish {
                    trackingFinish = true
                    firedFinishAlerts.removeAll()
                    let remaining = nav.distanceRemaining
                    if remaining > atTurnThreshold {
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
                speak("Last turn complete. \(formatVoiceDistance(remaining)) to finish.")
                markPassedThresholds(distance: remaining, into: &firedFinishAlerts)
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
                if canSpeak {
                    speak("Halfway point. \(formatVoiceDistance(nav.distanceRemaining)) remaining.")
                }
                return
            }
        }
    }

    private func fireDistanceAlert(
        distance: Double,
        speed: Double,
        fired: inout Set<Int>,
        atZeroText: String,
        approachText: (Double) -> String
    ) -> Bool {
        for (i, alertDist) in alertDistances.enumerated() {
            guard !fired.contains(i) else { continue }

            let isAtTurn = alertDist == 0
            let threshold = isAtTurn ? atTurnThreshold : alertDist
            guard distance <= threshold else { continue }

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
            return "in \(rounded) feet"
        }
        if feet < 300 {
            let hundreds = Int((feet / 100).rounded())
            return "in \(hundreds) hundred feet"
        }
        if miles < 0.2 {
            let rounded = Int((feet / 100).rounded()) * 100
            return "in \(rounded) feet"
        }
        if miles < 0.3 { return "in a quarter mile" }
        if miles < 0.6 { return "in half a mile" }
        if miles < 0.85 { return "in three quarters of a mile" }
        if miles < 1.1 { return "in 1 mile" }
        if miles < 1.3 { return "in about a mile" }
        if miles < 1.7 { return "in a mile and a half" }
        if miles < 2.2 { return "in 2 miles" }
        let rounded = Int(miles.rounded())
        return "in \(rounded) miles"
    }
}

extension TurnDirection {
    var voiceLabel: String {
        switch self {
        case .left:        return "turn left"
        case .slightLeft:  return "bear left"
        case .sharpLeft:   return "sharp left"
        case .right:       return "turn right"
        case .slightRight: return "bear right"
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
