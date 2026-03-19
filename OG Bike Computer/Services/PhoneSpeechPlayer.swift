//
//  PhoneSpeechPlayer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//

import AVFoundation
import UIKit
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "PhoneSpeechPlayer")

class PhoneSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = PhoneSpeechPlayer()

    private var synthesizer: AVSpeechSynthesizer
    private var isSessionConfigured = false
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid

    private override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        logger.notice("[PhoneSpeechPlayer] Speaking: \(text)")

        // Keep the process alive — HealthKit assertion only lasts ~1s
        beginBackgroundTask()
        configureSessionIfNeeded()

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            logger.error("[PhoneSpeechPlayer] activate error: \(error.localizedDescription)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    // Called when a new mirrored session arrives (including reconnections).
    // Recreates the synthesizer to avoid the silent-death bug.
    // Does NOT reconfigure the audio session — that's done once at app launch.
    func resetSession() {
        synthesizer.stopSpeaking(at: .immediate)
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        logger.notice("[PhoneSpeechPlayer] Session reset — fresh synthesizer")
    }

    // Called when the current session ends. Stops everything immediately.
    func stopImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("[PhoneSpeechPlayer] deactivate error: \(error.localizedDescription)")
        }
        endBackgroundTask()
        // Fresh synthesizer for next session
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
            isSessionConfigured = true
            logger.notice("[PhoneSpeechPlayer] Audio session configured")
        } catch {
            logger.error("[PhoneSpeechPlayer] session config error: \(error.localizedDescription)")
        }
    }

    private func beginBackgroundTask() {
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SpeechPlayback") { [weak self] in
            logger.warning("[PhoneSpeechPlayer] Background task expiring")
            self?.synthesizer.stopSpeaking(at: .immediate)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self?.endBackgroundTask()
        }
    }

    private func endBackgroundTask() {
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Don't deactivate if we interrupted one utterance to start another
        guard !synthesizer.isSpeaking else { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("[PhoneSpeechPlayer] deactivate error: \(error.localizedDescription)")
        }
        endBackgroundTask()
    }
}
