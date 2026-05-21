//
//  PhoneSpeechPlayer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//

#if !WIDGET_EXTENSION
import AVFoundation
#if os(iOS)
import UIKit
#endif
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "PhoneSpeechPlayer")

class PhoneSpeechPlayer: NSObject, AVSpeechSynthesizerDelegate, @unchecked Sendable {
    static let shared = PhoneSpeechPlayer()

    private var synthesizer: AVSpeechSynthesizer
    private var isSessionConfigured = false
    /// True while AVAudioSession is set active. Tracked separately from
    /// `isSessionConfigured` (which only reflects category setup) so we can
    /// honor predictive prewarm/release calls without re-doing category work
    /// or repeatedly toggling activation.
    private var isSessionActive = false
    /// Auto-release timer for arm TTL — if no speech arrives before this
    /// fires, the predictive system is wrong and we let the session idle.
    private var armReleaseTimer: Timer?
    #if os(iOS)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    /// Per-utterance bookkeeping for ack callbacks. Keyed by the utterance
    /// instance so we match the exact one that finished even when AVSpeech-
    /// Synthesizer queues multiple back-to-back.
    private var pendingAcks: [ObjectIdentifier: (id: UUID, onFinish: (UUID) -> Void)] = [:]

    private override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    /// Legacy entry point — speaks without an ack callback. Used by the
    /// WCSession path where there's no bidirectional ack channel.
    func speak(_ text: String) {
        speakInternal(text, id: nil, onFinish: nil)
    }

    /// Speaks `text` and invokes `onFinish(id)` when the underlying
    /// AVSpeechUtterance completes naturally. Used by the watch→phone
    /// mirror path so the watch knows real completion (vs. estimated).
    func speak(_ text: String, id: UUID, onFinish: @escaping (UUID) -> Void) {
        speakInternal(text, id: id, onFinish: onFinish)
    }

    private func speakInternal(_ text: String, id: UUID?, onFinish: ((UUID) -> Void)?) {
        logger.notice("[PhoneSpeechPlayer] Speaking: \(text)")

        // Keep the process alive — HealthKit assertion only lasts ~1s
        beginBackgroundTask()
        configureSessionIfNeeded()
        // Speech arriving counts as fulfilling the predictive arm — any
        // pending auto-release would be wrong now.
        armReleaseTimer?.invalidate()
        armReleaseTimer = nil

        if !isSessionActive {
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                isSessionActive = true
            } catch {
                logger.error("[PhoneSpeechPlayer] activate error: \(error.localizedDescription)")
            }
        }

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = PreferredVoice.resolved
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0
        if let id, let onFinish {
            pendingAcks[ObjectIdentifier(utterance)] = (id, onFinish)
        }
        // Don't stopSpeaking — the watch's VoiceAlertQueue is the priority arbiter
        // and won't dispatch a new alert until the previous one is considered finished.
        // AVSpeechSynthesizer naturally enqueues if speak() is called mid-utterance.
        synthesizer.speak(utterance)
    }

    // Called when a new mirrored session arrives (including reconnections).
    // Recreates the synthesizer to avoid the silent-death bug.
    // Does NOT reconfigure the audio session — that's done once at app launch.
    func resetSession() {
        synthesizer.stopSpeaking(at: .immediate)
        // Drop pending acks — the watch's queue will time out and recover
        // locally. Firing stale acks back would advance the new session's
        // queue prematurely.
        pendingAcks.removeAll()
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        logger.notice("[PhoneSpeechPlayer] Session reset — fresh synthesizer")
    }

    // Called when the current session ends. Stops everything immediately.
    func stopImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
        pendingAcks.removeAll()
        armReleaseTimer?.invalidate()
        armReleaseTimer = nil
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        } catch {
            logger.error("[PhoneSpeechPlayer] deactivate error: \(error.localizedDescription)")
        }
        isSessionConfigured = false
        isSessionActive = false
        endBackgroundTask()
        // Fresh synthesizer for next session
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    /// Pre-activate AVAudioSession ahead of an expected utterance. Idempotent
    /// — calling multiple times while already armed only resets the auto-
    /// release timer. Driven by VoiceLinkController on the watch side via
    /// `linkArm` messages so the first utterance after a stretch of silence
    /// doesn't pay the route-activation handshake.
    func prewarmAudioSession(ttl: TimeInterval) {
        configureSessionIfNeeded()
        if !isSessionActive {
            beginBackgroundTask()
            do {
                try AVAudioSession.sharedInstance().setActive(true)
                isSessionActive = true
                logger.notice("[PhoneSpeechPlayer] AVAudioSession pre-armed (ttl=\(ttl)s)")
            } catch {
                logger.error("[PhoneSpeechPlayer] prewarm activate error: \(error.localizedDescription)")
                endBackgroundTask()
                return
            }
        }
        // Reset the auto-release timer on every arm so the watch can extend
        // the window just by re-sending. If watch goes silent past `ttl`,
        // we release on our own as a failsafe.
        armReleaseTimer?.invalidate()
        let timer = Timer(timeInterval: max(5, ttl), repeats: false) { [weak self] _ in
            self?.releaseAudioSession()
        }
        RunLoop.main.add(timer, forMode: .common)
        armReleaseTimer = timer
    }

    /// True when a predictive arm is currently active (watch side asked us to
    /// hold AVAudioSession ready). Used by the stale-message filter to allow
    /// a slightly looser window when we know the watch intended this speech
    /// for the phone.
    var isAudioSessionArmedRecently: Bool {
        armReleaseTimer != nil
    }

    /// Release the predictive arm. Safe to call when not armed. Won't
    /// deactivate if a speech is currently playing — `didFinish` will
    /// handle that path.
    func releaseAudioSession() {
        armReleaseTimer?.invalidate()
        armReleaseTimer = nil
        guard isSessionActive else { return }
        if synthesizer.isSpeaking { return }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
            logger.notice("[PhoneSpeechPlayer] AVAudioSession released")
        } catch {
            logger.error("[PhoneSpeechPlayer] release error: \(error.localizedDescription)")
        }
        endBackgroundTask()
    }

    private func configureSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .allowBluetoothA2DP])
            isSessionConfigured = true
            logger.notice("[PhoneSpeechPlayer] Audio session configured")
        } catch {
            logger.error("[PhoneSpeechPlayer] session config error: \(error.localizedDescription)")
        }
    }

    private func beginBackgroundTask() {
        #if os(iOS)
        endBackgroundTask()
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SpeechPlayback") { [weak self] in
            logger.warning("[PhoneSpeechPlayer] Background task expiring")
            self?.synthesizer.stopSpeaking(at: .immediate)
            try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            self?.endBackgroundTask()
        }
        #endif
    }

    private func endBackgroundTask() {
        #if os(iOS)
        guard backgroundTaskID != .invalid else { return }
        UIApplication.shared.endBackgroundTask(backgroundTaskID)
        backgroundTaskID = .invalid
        #endif
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        // Fire ack for this utterance so the watch can advance its queue based
        // on real completion instead of a duration estimate. Done per-utterance
        // (not gated on isSpeaking) so a queue of utterances each ack in turn.
        if let entry = pendingAcks.removeValue(forKey: ObjectIdentifier(utterance)) {
            entry.onFinish(entry.id)
        }

        // Don't deactivate if we interrupted one utterance to start another
        guard !synthesizer.isSpeaking else { return }

        // If the watch still has the link armed (within TTL), hold the
        // session active for the next imminent alert instead of paying the
        // activation handshake again seconds from now. The watch's
        // `linkDisarm` (or our TTL failsafe) will release us.
        if armReleaseTimer != nil { return }

        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
        } catch {
            logger.error("[PhoneSpeechPlayer] deactivate error: \(error.localizedDescription)")
        }
        endBackgroundTask()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        // Treat cancellation as completion for ack purposes — the alert isn't
        // going to play, so the watch should move on rather than hang.
        if let entry = pendingAcks.removeValue(forKey: ObjectIdentifier(utterance)) {
            entry.onFinish(entry.id)
        }
    }
}
#endif // !WIDGET_EXTENSION
