//
//  PhoneSpeechPlayer.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/7/26.
//
//  The audio output endpoint for watch-originated voice navigation alerts.
//
//  Architecture (see plan §2.3 + §2.6):
//   • Category configured once, kept warm at app launch so the first activate
//     doesn't trigger a music interruption.
//   • AVAudioSession is ACTIVATED per-utterance and DEACTIVATED with
//     .notifyOthersOnDeactivation when the synthesizer queue drains. Music
//     ducks for the alert, returns to full volume after.
//   • Ack is fired on `didStart`, not `didFinish` — that's the signal the
//     watch uses to cancel its 800ms fallback timer. Acking at didStart
//     prevents double-speak (phone + watch both speaking) when network is
//     just slow rather than dead.
//   • A 1.5s safety timer per utterance handles the AVSpeechSynthesizer
//     "speak() called but didStart never fires" background bug. If it fires,
//     we deactivate the session (so music returns) and stay silent — the
//     watch's fallback timer will speak locally because no ack went out.

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

    // Per-utterance safety timer: if didStart doesn't fire within 1.5s of
    // speak(), assume the AVSpeechSynthesizer is wedged. Deactivate the
    // session so music returns to full volume, drop the pending ack so the
    // watch's 800ms fallback fires (no ack ever went out).
    private var safetyTimers: [ObjectIdentifier: Timer] = [:]
    private static let didStartSafetySeconds: TimeInterval = 1.5

    #if os(iOS)
    private var backgroundTaskID: UIBackgroundTaskIdentifier = .invalid
    #endif

    private override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    // MARK: Configuration

    /// Configure the AVAudioSession category. Idempotent. Cheap. Called at
    /// app launch and (defensively) on every speak() so we never speak with
    /// an unconfigured session. Doesn't activate.
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
    /// cancel-fallback signal — it's the watch's "okay, you're speaking,
    /// don't speak locally" trigger.
    func speak(_ text: String, id: UUID, onStart: @escaping (UUID) -> Void) {
        speakInternal(text, id: id, onStart: onStart)
    }

    /// Legacy entry point — speaks without an ack callback. Kept for
    /// callers that don't need cancel-fallback semantics (e.g. dev test
    /// buttons). Not used by the production alert path.
    func speak(_ text: String) {
        speakInternal(text, id: nil, onStart: nil)
    }

    /// Recreate the synthesizer on a fresh mirrored session arriving (e.g.
    /// HK reconnect after the iPhone app was relaunched). Drops in-flight
    /// state so stale acks from the dead session can't fire.
    func resetSession() {
        synthesizer.stopSpeaking(at: .immediate)
        clearPending()
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
        logger.notice("[Speech] Session reset — fresh synthesizer")
    }

    /// Workout ended. Stop everything immediately and tear down.
    func stopImmediately() {
        synthesizer.stopSpeaking(at: .immediate)
        clearPending()
        deactivateSession(reason: "stopImmediately")
        // Leave isSessionConfigured = true — keeping the category alive
        // means the next utterance after a new workout doesn't pay the
        // category-change-causes-music-interruption tax described above.
        synthesizer = AVSpeechSynthesizer()
        synthesizer.delegate = self
    }

    // MARK: Internals

    private func speakInternal(_ text: String, id: UUID?, onStart: ((UUID) -> Void)?) {
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

        // Safety timer: if didStart doesn't fire within 1.5s, the
        // AVSpeechSynthesizer background-queueing bug bit us. Drop the
        // pending ack and deactivate so music returns. Watch's 800ms
        // fallback will have already fired or be about to.
        let timer = Timer(timeInterval: Self.didStartSafetySeconds, repeats: false) { [weak self] _ in
            self?.handleSafetyTimeout(utteranceKey: key, id: id)
        }
        RunLoop.main.add(timer, forMode: .common)
        safetyTimers[key] = timer

        // Don't stopSpeaking here. The watch's queue is the priority arbiter
        // for now; multiple speak() calls in a row queue naturally on
        // AVSpeechSynthesizer and play in order.
        synthesizer.speak(utterance)
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
        safetyTimers.values.forEach { $0.invalidate() }
        safetyTimers.removeAll()
    }

    private func handleSafetyTimeout(utteranceKey: ObjectIdentifier, id: UUID?) {
        // Race-safe: timer can fire concurrently with didStart on the main
        // queue. If safetyTimers no longer has this key, didStart already
        // cleaned up — bail.
        guard safetyTimers.removeValue(forKey: utteranceKey) != nil else { return }
        let pending = pendingStarts.removeValue(forKey: utteranceKey)
        let logID = pending?.id.uuidString.prefix(8) ?? id?.uuidString.prefix(8) ?? "no-id"
        logger.error("[Speech] SAFETY TIMEOUT id=\(logID) — didStart never fired after \(Self.didStartSafetySeconds)s. Deactivating, watch fallback will speak.")

        // Stop the wedged utterance. Don't ack — that's what tells the
        // watch to fall back.
        synthesizer.stopSpeaking(at: .immediate)
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
        let key = ObjectIdentifier(utterance)
        // Cancel the safety timer first — it can race with this callback on
        // the same queue, and a late safety fire would wrongly deactivate
        // the still-playing utterance.
        safetyTimers.removeValue(forKey: key)?.invalidate()
        if let entry = pendingStarts.removeValue(forKey: key) {
            logger.notice("[Speech] didStart id=\(entry.id.uuidString.prefix(8)) — ack")
            entry.onStart(entry.id)
        } else {
            logger.info("[Speech] didStart (no ack registered)")
        }
        // One-line route log per utterance so we can confirm AirPods/wired/
        // built-in speaker routing per alert in the testing matrix (plan §5).
        logCurrentRoute()
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        // Defensive cleanup — didStart should already have removed both, but
        // pathological cases (interruption before didStart) hit here.
        safetyTimers.removeValue(forKey: key)?.invalidate()
        pendingStarts.removeValue(forKey: key)

        // Critical: only deactivate when the queue is *actually* drained.
        // Chained utterances share one session activation — no inter-
        // utterance deactivate flicker (which would cause an audible duck-
        // unduck-duck cycle).
        guard !synthesizer.isSpeaking else {
            logger.info("[Speech] didFinish but more utterances queued — staying active")
            return
        }
        logger.notice("[Speech] didFinish — queue drained")
        deactivateSession(reason: "queue drained")
    }

    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let key = ObjectIdentifier(utterance)
        safetyTimers.removeValue(forKey: key)?.invalidate()
        pendingStarts.removeValue(forKey: key)
        guard !synthesizer.isSpeaking else { return }
        logger.notice("[Speech] didCancel — queue drained")
        deactivateSession(reason: "cancelled")
    }
}
#endif // !WIDGET_EXTENSION
