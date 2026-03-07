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

    // 0 is always appended as the "at turn" trigger
    private let alertDistances: [Double] = [
        402.336,  // ¼ mile
        30.48,    // 100 feet
        0         // at the turn
    ]

    private let atTurnThreshold: Double = 20       // meters — "close enough" to 0
    private let cooldown: TimeInterval = 6          // min gap between announcements
    private let minTimeBeforeTurn: TimeInterval = 4 // suppress if turn is this close in seconds

    // State
    private var currentTurnIndex: Int?
    private var firedTurnAlerts: Set<Int> = []      // indices into alertDistances

    private var trackingFinish = false
    private var firedFinishAlerts: Set<Int> = []

    private var announcedHalfway = false
    private var announcedArrival = false
    private var announcedOffRoute = false
    private var wasOffRoute = false
    private var lastAnnouncementTime: Date = .distantPast

    private let synthesizer = AVSpeechSynthesizer()
    weak var workoutManager: WorkoutManager?

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func reset() {
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
    }

    func configureAudioSession() {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("VoiceNavigator audio session config error: \(error)")
        }
    }

    // Main update — call every location update

    func update(nav: NavigationTracker, speed: Double) {
        guard isEnabled else { return }
        guard let route = nav.processedRoute else { return }

        // --- Route complete (arrival) ---
        if nav.isRouteComplete {
            if !announcedArrival {
                announcedArrival = true
                speak("You have arrived. Route complete.")
            }
            return
        }

        // --- Off-route / back on route ---
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
            // Re-announce upcoming turn after returning
            if let turn = nav.nextTurn {
                let dist = nav.distanceToNextTurn
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) { [weak self] in
                    self?.speak("\(self?.formatVoiceDistance(dist) ?? ""), \(turn.direction.voiceLabel).")
                }
            }
            return
        }

        // --- Turn change detection (post-turn announcement) ---
        if let turn = nav.nextTurn, turn.index != currentTurnIndex {
            let passedTurn = currentTurnIndex != nil
            currentTurnIndex = turn.index
            firedTurnAlerts.removeAll()
            trackingFinish = false
            firedFinishAlerts.removeAll()

            if passedTurn {
                // Just passed a turn — announce the next one with full distance
                let dist = nav.distanceToNextTurn
                speak("\(formatVoiceDistance(dist)), \(turn.direction.voiceLabel).")
                markPassedThresholds(distance: dist, into: &firedTurnAlerts)
                return
            }
        }

        // --- Turn distance alerts ---
        if let turn = nav.nextTurn {
            if fireDistanceAlert(
                distance: nav.distanceToNextTurn,
                speed: speed,
                fired: &firedTurnAlerts,
                atZeroText: "\(turn.direction.voiceLabel.localizedCapitalized).",
                approachText: { d in "\(self.formatVoiceDistance(d)), \(turn.direction.voiceLabel)." }
            ) { return }

            // If this is the last turn, also watch for finish after it
            let isLastTurn = route.turnPoints.last?.index == turn.index
            if isLastTurn, firedTurnAlerts.contains(alertDistances.count - 1) {
                // At-turn alert fired for last turn — transition to finish tracking
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

        // --- Finish distance alerts (no turns remaining) ---
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

        // --- Halfway ---
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

    /// Checks each alert threshold for the given distance. Returns true if an alert fired.
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

            // Cooldown — at-turn always fires
            if !isAtTurn && !canSpeak { continue }

            // Speed-based suppression: if we'd reach the turn before the
            // min gap, skip this intermediate alert and let the at-turn fire
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

    private func announceOnce(_ text: String) {
        guard canSpeak else { return }
        speak(text)
    }

    private func speak(_ text: String) {
        lastAnnouncementTime = Date()

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

        // Under ~150 feet — round to 50
        if feet < 150 {
            let rounded = max(50, Int((feet / 50).rounded()) * 50)
            return "in \(rounded) feet"
        }

        // Under ~300 feet — round to 100
        if feet < 300 {
            let hundreds = Int((feet / 100).rounded())
            return "in \(hundreds) hundred feet"
        }

        // Under 0.2 miles
        if miles < 0.2 {
            let rounded = Int((feet / 100).rounded()) * 100
            return "in \(rounded) feet"
        }

        // Quarter mile neighborhood
        if miles < 0.3 {
            return "in a quarter mile"
        }

        // Half mile
        if miles < 0.6 {
            return "in half a mile"
        }

        // Three quarters
        if miles < 0.85 {
            return "in three quarters of a mile"
        }

        // ~1 mile
        if miles < 1.1 {
            return "in 1 mile"
        }

        // 1-2 miles — use "mile and a half" etc.
        if miles < 1.3 {
            return "in about a mile"
        }
        if miles < 1.7 {
            return "in a mile and a half"
        }
        if miles < 2.2 {
            return "in 2 miles"
        }

        // 2+ miles — round
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

// NOTE: In WorkoutView, uncomment the voice toggle onChange:
//   .onChange(of: voiceEnabled) { _, newValue in
//       VoiceNavigator.shared.isEnabled = newValue
//   }

extension VoiceNavigator: AVSpeechSynthesizerDelegate {
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("VoiceNavigator deactivate error: \(error)")
        }
    }
}
