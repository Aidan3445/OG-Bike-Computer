//
//  PhoneSpeechPlayer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//

import AVFoundation

class PhoneSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = PhoneSpeechPlayer()

    private let synthesizer = AVSpeechSynthesizer()
    private var isSessionConfigured = false

    private override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        print("[PhoneSpeech] Speaking: \(text)")
        configureSessionIfNeeded()

        do {
            try AVAudioSession.sharedInstance().setActive(true)
        } catch {
            print("[PhoneSpeech] activate error: \(error)")
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "en-US")
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        synthesizer.stopSpeaking(at: .word)
        synthesizer.speak(utterance)
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, options: [.duckOthers])
            isSessionConfigured = true
            print("[PhoneSpeech] Audio session configured")
        } catch {
            print("[PhoneSpeech] session config error: \(error)")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            print("[PhoneSpeech] deactivate error: \(error)")
        }
    }
}
