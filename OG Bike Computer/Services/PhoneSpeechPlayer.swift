//
//  PhoneSpeechPlayer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//
//  The audio output endpoint for watch-originated voice navigation alerts.
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
    /// Tracks whether `setCategory` has been called this app session.
    /// Cheap to redo, but logging spam is annoying.
    private var isSessionConfigured = false
    /// True between `setActive(true)` and `setActive(false, notifyOthers)`.
    /// Used to avoid re-activating (no-op flicker) and to gate the
    /// deactivate-on-drain logic.
    private var isSessionActive = false

    // Per-utterance ack state — keyed by the utterance object so each one
    // acks independently when AVSpeechSynthesizer queues multiple back-to-
    // back. Ack fires on didStart (not didFinish) so the watch can cancel
    // its fallback timer before this utterance has finished playing.
    private var pendingStarts: [ObjectIdentifier: (id: UUID, onStart: (UUID) -> Void)] = [:]

    // Per-utterance finish callbacks — fired on didFinish/didCancel so the
    // watch can pace multi-line readouts on real completion.
    private var pendingFinishes: [ObjectIdentifier: (id: UUID, onFinish: (UUID) -> Void)] = [:]

    // Per-utterance safety timer: if didStart doesn't fire within 1.5s of
    // when the synthesizer should start this utterance, assume it's wedged.
    // Deactivate the session so music returns to full volume, drop the
    // pending ack so the watch's 800ms fallback fires (no ack ever went out).
    private var safetyTimers: [ObjectIdentifier: Timer] = [:]
    private static let didStartSafetySeconds: TimeInterval = 1.5

    // Ordered list of utterances we've handed to AVSpeechSynthesizer but
    // haven't seen didFinish/didCancel for.    
    private var utteranceQueue: [ObjectIdentifier] = []

    #if os(iOS)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    private override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Configuration

    /// Configure the AVAudioSession category.  
    func configureAudioSessionIfNeeded() {
        guard !isSessionConfigured else { return }
        let session = AVAudioSession.sharedInstance()
        do {
            // .playback     — allow background playback + ducking.
            // .voicePrompt  — TTS-tuned ducking ramp; what Apple Maps uses
            //                  for turn-by-turn navigation prompts.
            // .duckOthers   — music dims during the utterance, restores
            //                  when we deactivate with .notifyOthers.
            //
            // No policy override — `.longFormAudio` is INCOMPATIBLE with
            // `.duckOthers` (OSStatus -50). LongForm is for music/podcasts
            // that own the audio focus; nav prompts are short ducking
            // interruptions, which is the default policy.
            //
            // BT A2DP is implicit for .playback so we don't pass
            // .allowBluetoothA2DP. .allowBluetoothHFP would route to
            // hands-free call audio which is wrong for music ducking.
            try session.setCategory(
                .playback,
                mode: .voicePrompt,
                options: [.duckOthers]
            )
            isSessionConfigured = true
            logger.notice("[Speech] AVAudioSession category configured (.playback/.voicePrompt/.duckOthers)")
        } catch {
            logger.error("[Speech] setCategory failed: \(error.localizedDescription)")
        }
    }

    // MARK: Public API

    /// Speak `text` and fire `onStart(id)` when AVSpeechSynthesizer reports
    /// the utterance has actually begun. The onStart callback is the
    /// cancel-fallback signal
    func speak(_ text: String, id: UUID, onStart: @escaping (UUID) -> Void, onFinish: ((UUID) -> Void)? = nil) {
        onMain { self.speakInternal(text, id: id, onStart: onStart, onFinish: onFinish) }
    }

    /// Legacy entry point — speaks without an ack callback. Kept for
    /// callers that don't need cancel-fallback semantics
    func speak(_ text: String) {
        onMain { self.speakInternal(text, id: nil, onStart: nil, onFinish: nil) }
    }

    /// Recreate the synthesizer on a fresh mirrored session arriving (e.g.
    /// HK reconnect after the iPhone app was relaunched). Drops in-flight
    /// state so stale acks from the dead session can't fire.
    func resetSession() {
        onMain {
            self.synthesizer.stopSpeaking(at: .immediate)
            self.clearPending()
            self.synthesizer = AVSpeechSynthesizer()
            self.synthesizer.delegate = self
            logger.notice("[Speech] Session reset — fresh synthesizer")
        }
    }

    /// Workout ended. Stop everything immediately and tear down.
    func stopImmediately() {
        onMain {
            self.synthesizer.stopSpeaking(at: .immediate)
            self.clearPending()
            self.deactivateSession(reason: "stopImmediately")
            // Leave isSessionConfigured = true — keeping the category alive
            // means the next utterance after a new workout doesn't pay the
            // category-change-causes-music-interruption tax described above.
            self.synthesizer = AVSpeechSynthesizer()
            self.synthesizer.delegate = self
        }
    }

    // MARK: Internals

    /// All mutable state (session flags, utterance queue, pending acks,
    /// timers) is confined to the main queue. Entry points arrive on
    /// WCSession's callback queue and delegate callbacks on the
    /// synthesizer's — funnel everything through here.
    private func onMain(_ block: @escaping () -> Void) {
        if Thread.isMainThread {
            block()
        } else {
            DispatchQueue.main.async(execute: block)
        }
    }

    private func speakInternal(_ text: String, id: UUID?, onStart: ((UUID) -> Void)?, onFinish: ((UUID) -> Void)?) {
        let logID = id?.uuidString.prefix(8) ?? "no-id"
        logger.notice("[Speech] speak(id=\(logID)) text=\"\(text)\"")

        configureAudioSessionIfNeeded()
        beginBackgroundTask()
        activateSessionIfNeeded(id: id)

        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = PreferredVoice.resolved
        utterance.rate = AVSpeechUtteranceDefaultSpeechRate * 1.1
        utterance.pitchMultiplier = 1.05
        utterance.volume = 1.0

        let key = ObjectIdentifier(utterance)
        if let id, let onStart {
            pendingStarts[key] = (id, onStart)
        }
        if let id, let onFinish {
            pendingFinishes[key] = (id, onFinish)
        }

        // Only arm the safety timer when this utterance will actually start
        // now (synth was idle / our tracked queue is empty). For utterances
        // queued behind others, didFinish arms the next one's timer as each
        // completes — otherwise back-to-back speak() calls (split readouts)
        // would all arm at t=0 and false-fire 1.5s later before their turn.
        utteranceQueue.append(key)
        if utteranceQueue.count == 1 {
            armSafetyTimer(for: key, id: id)
        }

        // Don't stopSpeaking here. The watch's queue is the priority arbiter
        // for now; multiple speak() calls in a row queue naturally on
        // AVSpeechSynthesizer and play in order.
        synthesizer.speak(utterance)
    }

    private func armSafetyTimer(for key: ObjectIdentifier, id: UUID?) {
        let timer = Timer(timeInterval: Self.didStartSafetySeconds, repeats: false) { [weak self] _ in
            self?.handleSafetyTimeout(utteranceKey: key, id: id)
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimers[key] = timer
    }

    private func activateSessionIfNeeded(id: UUID?) {
        guard !isSessionActive else { return }
        do {
            try AVAudioSession.sharedInstance().setActive(true)
            isSessionActive = true
            let logID = id?.uuidString.prefix(8) ?? "no-id"
            logger.notice("[Speech] setActive(true) for id=\(logID)")
        } catch {
            logger.error("[Speech] setActive(true) failed: \(error.localizedDescription)")
        }
    }

    /// Deactivate with .notifyOthersOnDeactivation so other audio apps
    /// (Spotify, Apple Music, podcasts) restore to full volume. Safe to
    /// call when already inactive — short-circuits.
    private func deactivateSession(reason: String) {
        guard isSessionActive else {
            endBackgroundTask()
            return
        }
        do {
            try AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
            isSessionActive = false
            logger.notice("[Speech] setActive(false, notifyOthers) — \(reason)")
        } catch {
            logger.error("[Speech] setActive(false) failed: \(error.localizedDescription)")
        }
        endBackgroundTask()
    }

    private func clearPending() {
        pendingStarts.removeAll()
        pendingFinishes.removeAll()
        safetyTimers.values.forEach { $0.invalidate() }
        safetyTimers.removeAll()
        utteranceQueue.removeAll()
    }

    private func handleSafetyTimeout(utteranceKey: ObjectIdentifier, id: UUID?) {
        // Race-safe: timer can fire concurrently with didStart on the main
        // queue. If safetyTimers no longer has this key, didStart already
        // cleaned up — bail.
        guard safetyTimers.removeValue(forKey: utteranceKey) != nil else { return }
        let pending = pendingStarts.removeValue(forKey: utteranceKey)
        let logID = pending?.id.uuidString.prefix(8) ?? id?.uuidString.prefix(8) ?? "no-id"
        logger.error("[Speech] SAFETY TIMEOUT id=\(logID) — didStart never fired after \(Self.didStartSafetySeconds)s. Deactivating, watch fallback will speak.")

        // stopSpeaking(.immediate) flushes the whole synth queue — including
        // any utterances queued behind the wedged one. Clear our tracking
        // and drop their pending acks so late didFinish callbacks for the
        // flushed utterances don't try to arm a timer for a gone utterance.
        synthesizer.stopSpeaking(at: .immediate)
        clearPending()
        deactivateSession(reason: "safety timeout")

        // Log current route for diagnostics — were we pointing at the right
        // output when this failed?
        logCurrentRoute()
    }

    private func logCurrentRoute() {
        let outputs = AVAudioSession.sharedInstance().currentRoute.outputs
        let desc = outputs.map { "\($0.portType.rawValue):\($0.portName)" }.joined(separator: ",")
        logger.info("[Speech] currentRoute outputs=[\(desc)]")
    }

    // MARK: Background task

    private func beginBackgroundTask() {
        #if os(iOS)
        guard backgroundTaskID == .invalid else { return }
        backgroundTaskID = UIApplication.shared.beginBackgroundTask(withName: "SpeechPlayback") { [weak self] in
            logger.warning("[Speech] Background task expiring")
            self?.synthesizer.stopSpeaking(at: .immediate)
            self?.deactivateSession(reason: "bg task expiring")
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

    // MARK: AVSpeechSynthesizerDelegate

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        onMain {
            let key = ObjectIdentifier(utterance)
            // Cancel the safety timer first — it can race with this callback
            // on the same queue, and a late safety fire would wrongly
            // deactivate the still-playing utterance.
            self.safetyTimers.removeValue(forKey: key)?.invalidate()
            if let entry = self.pendingStarts.removeValue(forKey: key) {
                logger.notice("[Speech] didStart id=\(entry.id.uuidString.prefix(8)) — ack")
                entry.onStart(entry.id)
            } else {
                logger.info("[Speech] didStart (no ack registered)")
            }
            // One-line route log per utterance so we can confirm AirPods/
            // wired/built-in speaker routing per alert in the testing matrix
            // (plan §5).
            self.logCurrentRoute()
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        onMain {
            let key = ObjectIdentifier(utterance)
            // Defensive cleanup — didStart should already have removed both,
            // but pathological cases (interruption before didStart) hit here.
            self.safetyTimers.removeValue(forKey: key)?.invalidate()
            self.pendingStarts.removeValue(forKey: key)
            if let entry = self.pendingFinishes.removeValue(forKey: key) {
                logger.notice("[Speech] didFinish id=\(entry.id.uuidString.prefix(8)) — finish signal")
                entry.onFinish(entry.id)
            }
            self.advanceUtteranceQueue(finishedKey: key)

            // Critical: only deactivate when the queue is *actually* drained.
            // Chained utterances share one session activation — no inter-
            // utterance deactivate flicker (which would cause an audible
            // duck-unduck-duck cycle). Checking our own tracked queue (not
            // synthesizer.isSpeaking) so a speak() serialized behind this
            // callback can't observe a stale answer.
            guard self.utteranceQueue.isEmpty else {
                logger.info("[Speech] didFinish but more utterances queued — staying active")
                return
            }
            logger.notice("[Speech] didFinish — queue drained")
            self.deactivateSession(reason: "queue drained")
        }
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        onMain {
            let key = ObjectIdentifier(utterance)
            self.safetyTimers.removeValue(forKey: key)?.invalidate()
            self.pendingStarts.removeValue(forKey: key)
            // A cancelled utterance still resolves its finish signal — the
            // phone is done with it either way, and the watch must not
            // stall its queue waiting on a line that will never complete.
            if let entry = self.pendingFinishes.removeValue(forKey: key) {
                entry.onFinish(entry.id)
            }
            self.advanceUtteranceQueue(finishedKey: key)
            guard self.utteranceQueue.isEmpty else { return }
            logger.notice("[Speech] didCancel — queue drained")
            self.deactivateSession(reason: "cancelled")
        }
    }

    /// Drop `finishedKey` from the tracked queue and arm the safety timer
    /// for the new head (the utterance the synth is about to start). No-op
    /// when the queue is empty or the new head already has a timer.
    private func advanceUtteranceQueue(finishedKey: ObjectIdentifier) {
        utteranceQueue.removeAll { $0 == finishedKey }
        guard let next = utteranceQueue.first, safetyTimers[next] == nil else { return }
        armSafetyTimer(for: next, id: pendingStarts[next]?.id)
    }
}
#endif // !WIDGET_EXTENSION
