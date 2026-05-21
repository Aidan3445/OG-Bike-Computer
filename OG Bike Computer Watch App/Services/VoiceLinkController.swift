//
//  VoiceLinkController.swift
//  OG Bike Computer Watch App
//

import Foundation
import Combine

/// Confidence in the watch→phone speech link, used by VoiceNavigator to decide
/// whether to even attempt phone-mirrored speech for a given alert.
///
/// `.none`   — no recent successful heartbeat; routing should fall straight to
///              the watch speaker rather than attempting a doomed phone send.
/// `.warm`   — the mirror channel just round-tripped a heartbeat; the phone is
///              there, but its AVAudioSession isn't yet active so the first
///              utterance would still pay the activation handshake.
/// `.primed` — channel warm AND the phone has confirmed AVAudioSession is
///              pre-activated. Speech can fire with minimal first-utterance
///              latency.
enum LinkConfidence: Int, Comparable {
    case none = 0, warm = 1, primed = 2
    static func < (l: LinkConfidence, r: LinkConfidence) -> Bool { l.rawValue < r.rawValue }
}

/// Owns the predictive warm-up + confidence signal for phone-mirrored speech.
///
/// Two layers:
///  • Channel heartbeat (cheap, always-on during a ride): low-rate `linkPing`
///    over the HKWorkoutSession mirror so we always know if the phone is
///    actually reachable, not just whether `startMirroringToCompanionDevice`
///    eventually called back.
///  • Audio-session arm (expensive, predictive): tell the phone to
///    pre-activate AVAudioSession ~N seconds before an alert is expected,
///    based on ETA derived from speed + grade + distance-to-next-turn. Hold
///    through the post-speech cool-down, then disarm so we're not ducking
///    music or burning battery between turns.
final class VoiceLinkController {
    static let shared = VoiceLinkController()

    @Published private(set) var linkConfidence: LinkConfidence = .none

    weak var workoutManager: WorkoutManager?

    // Channel layer
    private var heartbeatTimer: Timer?
    private var lastPingAckAt: Date = .distantPast

    // Audio-session arm layer
    private var armRequested = false
    private var lastArmSentAt: Date = .distantPast
    private var lastArmAckAt: Date = .distantPast
    private var lastSpeechAckAt: Date = .distantPast

    // Off-route + back-on-route prediction state
    private var wasOffRoute = false
    private var nearestDistanceHistory: [(t: Date, d: Double)] = []

    // Tuning
    private static let heartbeatInterval: TimeInterval = 5.0
    /// Ack received within this window → channel is healthy enough for `.warm`.
    private static let warmWindow: TimeInterval = 12.0
    /// Arm-ack within this window → `.primed`.
    private static let primedWindow: TimeInterval = 18.0
    /// Don't re-send `linkArm` faster than this while already armed.
    private static let armResendInterval: TimeInterval = 3.0
    /// Phone auto-releases AVAudioSession this long after the last arm
    /// message if no speech or disarm arrives (failsafe).
    private static let armTTL: TimeInterval = 25.0
    /// Hold the arm this long after a speech ack so back-to-back alerts
    /// (split + turn, off-route + missed-turn) share one activation.
    private static let armCooldownSeconds: TimeInterval = 6.0
    /// Lead time bounds — clamps the speed/grade-adaptive formula.
    private static let baseLeadSeconds: TimeInterval = 6.0
    private static let minLeadSeconds: TimeInterval = 4.0
    private static let maxLeadSeconds: TimeInterval = 15.0
    /// Speed floor for ETA math — keeps stationary/walking pace from making
    /// every upcoming event look "imminent" forever.
    private static let minSpeedFloorMps: Double = 1.5
    /// Back-on-route arm trigger: nearest-distance below this AND shrinking.
    private static let backOnRouteArmDistanceMeters: Double = 60.0
    /// Negative because we want closing rate ≤ this (e.g. ≤ -1 m/s).
    private static let backOnRouteShrinkRateMps: Double = -1.0

    // MARK: Lifecycle

    /// Start the heartbeat + reset all state for a fresh ride.
    func start(workoutManager: WorkoutManager) {
        self.workoutManager = workoutManager
        linkConfidence = .none
        lastPingAckAt = .distantPast
        lastArmAckAt = .distantPast
        lastArmSentAt = .distantPast
        lastSpeechAckAt = .distantPast
        armRequested = false
        wasOffRoute = false
        nearestDistanceHistory.removeAll()

        // Kick a ping immediately so we don't wait 5s for the first
        // confidence signal on ride start.
        sendPing()

        heartbeatTimer?.invalidate()
        heartbeatTimer = Timer.scheduledTimer(withTimeInterval: Self.heartbeatInterval, repeats: true) { [weak self] _ in
            self?.sendPing()
        }
        log("started")
    }

    func stop() {
        heartbeatTimer?.invalidate()
        heartbeatTimer = nil
        if armRequested {
            sendDisarm()
        }
        armRequested = false
        let prev = linkConfidence
        linkConfidence = .none
        if prev != .none { log("confidence: \(prev) → none (stopped)") }
        workoutManager = nil
    }

    /// Called from WorkoutManager on every location update — the same tick
    /// that drives VoiceNavigator. Decides whether to arm/disarm and refreshes
    /// the confidence signal.
    func update(navigation: NavigationTracker, speed: Double, averageSpeed: Double, grade: Double) {
        recomputeConfidence()

        guard let wm = workoutManager else { return }

        // No route loaded → nothing predictive to schedule; just keep the
        // channel warm in case the rider loads a route mid-ride.
        guard wm.hasRoute else {
            ensureDisarmedIfIdle()
            return
        }

        let now = Date()

        // Off-route: arm immediately and hold until back on route. The
        // off-route announcement, any missed-turn voice, and subsequent
        // back-on-route confirmation should all play on the same primed link.
        if navigation.isOffRoute {
            if !wasOffRoute {
                log("offRoute=true → arm")
                wasOffRoute = true
            }
            ensureArmed(reason: "offRoute")
            return
        }
        if wasOffRoute {
            wasOffRoute = false
            log("offRoute=false")
            // fall through — back-on-route alert might still be pending; arm
            // stays held by lastSpeechAckAt cool-down once it plays.
        }

        // Back-on-route prediction: only warm when distance to route is
        // actually shrinking AND below a sensible threshold. A rider on a
        // parallel road 300m offset shouldn't keep the phone armed.
        nearestDistanceHistory.append((now, navigation.nearestRouteDistance))
        nearestDistanceHistory.removeAll { now.timeIntervalSince($0.t) > 10 }
        let shrinkRate = computeShrinkRate(history: nearestDistanceHistory)
        if navigation.nearestRouteDistance > 0,
           navigation.nearestRouteDistance < Self.backOnRouteArmDistanceMeters,
           shrinkRate < Self.backOnRouteShrinkRateMps {
            ensureArmed(reason: "backOnRoutePredict")
            return
        }

        // Predictive: arm when the soonest upcoming event's ETA is within the
        // adaptive lead window.
        let effectiveSpeed = max(speed, averageSpeed * 0.5, Self.minSpeedFloorMps)
        let lead = audioArmLeadSeconds(speed: speed, grade: grade)
        if let eta = nextEventETA(navigation: navigation, wm: wm, effectiveSpeed: effectiveSpeed),
           eta <= lead {
            ensureArmed(reason: "etaWithinLead(eta=\(format(eta))s,lead=\(format(lead))s)")
            return
        }

        // No imminent event — release after speech cool-down so the music
        // duck doesn't sit on top of an idle stretch between turns.
        ensureDisarmedIfIdle()
    }

    // MARK: Lead-time math

    /// Adaptive lead time: short by default, expands when speed is low
    /// (stop-and-go makes ETA unreliable) or grade is steep (rider may
    /// accelerate quickly on a descent and arrive sooner than expected).
    func audioArmLeadSeconds(speed: Double, grade: Double) -> TimeInterval {
        var lead = Self.baseLeadSeconds

        // Speed uncertainty: at 0 m/s add up to +6s; ramp to 0 by 5 m/s.
        let s = max(0, min(speed, 5.0))
        lead += (5.0 - s) / 5.0 * 6.0

        // Grade uncertainty: only penalize *descents* — a -10% grade can
        // double speed in seconds. Climbs slow the rider so ETA stays loose.
        if grade < -3 {
            lead += min(abs(grade) - 3, 7) * 0.3   // up to +2.1s at -10%
        }

        return min(max(lead, Self.minLeadSeconds), Self.maxLeadSeconds)
    }

    /// Find the soonest upcoming alert event and return its ETA in seconds.
    /// Returns nil when nothing is in range or speed is too low to predict.
    private func nextEventETA(navigation: NavigationTracker, wm: WorkoutManager, effectiveSpeed: Double) -> TimeInterval? {
        guard effectiveSpeed > 0 else { return nil }

        let prefs = wm.navigationAlerts
        var bestETA: TimeInterval = .infinity

        // Turn: first approach distance (largest non-zero threshold) is when
        // the alert fires. Use that as the predictive trigger point.
        if let _ = navigation.nextTurn {
            let approachDist = prefs.turnAlerts.secondaryApproachEnabled
                ? prefs.turnAlerts.secondaryApproachDistance
                : prefs.turnAlerts.primaryApproachDistance
            let distToFire = navigation.distanceToNextTurn - approachDist
            if distToFire > 0 {
                bestETA = min(bestETA, distToFire / effectiveSpeed)
            } else {
                // We're already inside the approach band → fire is imminent.
                bestETA = 0
            }
        }

        // Splits: distance to next split boundary.
        if prefs.splitAlerts.enabled, prefs.splitAlerts.splitDistance > 0 {
            let splitDist = prefs.splitAlerts.splitDistance
            let traveled = wm.totalDistance
            let nextSplit = (floor(traveled / splitDist) + 1) * splitDist
            let distToSplit = nextSplit - traveled
            if distToSplit > 0 {
                bestETA = min(bestETA, distToSplit / effectiveSpeed)
            }
        }

        // Arrival: distance remaining.
        if navigation.distanceRemaining > 0 {
            // Arrival fires when distance remaining hits ~atTurn threshold,
            // but we want to arm before then — use the raw remaining.
            let arrivalETA = navigation.distanceRemaining / effectiveSpeed
            // Only consider arrival if it's actually close — otherwise we'd
            // arm-permanently on a 100km route. 90s out is plenty.
            if arrivalETA < 90 {
                bestETA = min(bestETA, arrivalETA)
            }
        }

        // Waypoints/halfway: not predicted individually here — the turn-band
        // arm window above will typically cover them since waypoint approach
        // distances are similar to turn approach distances.

        return bestETA.isFinite ? bestETA : nil
    }

    /// Approximate d(distance)/dt over the recent history window via simple
    /// linear regression slope (least squares). Negative means closing.
    private func computeShrinkRate(history: [(t: Date, d: Double)]) -> Double {
        guard history.count >= 3 else { return 0 }
        let t0 = history[0].t.timeIntervalSinceReferenceDate
        let xs = history.map { $0.t.timeIntervalSinceReferenceDate - t0 }
        let ys = history.map { $0.d }
        let n = Double(xs.count)
        let sumX = xs.reduce(0, +)
        let sumY = ys.reduce(0, +)
        let sumXY = zip(xs, ys).reduce(0) { $0 + $1.0 * $1.1 }
        let sumXX = xs.reduce(0) { $0 + $1 * $1 }
        let denom = n * sumXX - sumX * sumX
        guard abs(denom) > 1e-6 else { return 0 }
        return (n * sumXY - sumX * sumY) / denom
    }

    // MARK: Arm state machine

    private func ensureArmed(reason: String) {
        let now = Date()
        if !armRequested {
            armRequested = true
            log("arm requested (\(reason))")
            sendArm()
            return
        }
        if now.timeIntervalSince(lastArmSentAt) >= Self.armResendInterval {
            sendArm()
        }
    }

    private func ensureDisarmedIfIdle() {
        guard armRequested else { return }
        let now = Date()
        // Don't release while a recent alert ack is still inside the cool-down.
        if now.timeIntervalSince(lastSpeechAckAt) < Self.armCooldownSeconds {
            return
        }
        armRequested = false
        sendDisarm()
        log("disarm (idle past cooldown)")
    }

    /// Called by VoiceNavigator (via WorkoutManager bridge) when a phone
    /// speech ack arrives, so we hold the arm a few seconds past it instead
    /// of immediately releasing.
    func notePhoneSpeechAck() {
        lastSpeechAckAt = Date()
    }

    /// Called when a phone send failed — drop confidence so the next route
    /// decision falls back to watch local instead of trying again blindly.
    func notePhoneSendFailure() {
        log("phone send failure → ping immediately")
        // Force an immediate probe so we re-establish confidence quickly
        // rather than waiting up to 5s for the next heartbeat tick.
        sendPing()
    }

    // MARK: Message send / ack handling

    private func sendPing() {
        guard let wm = workoutManager else { return }
        let id = UUID()
        let payload: [String: String] = [
            "type": "linkPing",
            "id": id.uuidString,
            "ts": String(Date().timeIntervalSince1970)
        ]
        wm.sendMirrorPayload(payload) { [weak self] success in
            if !success {
                // Send itself failed — leave lastPingAckAt alone; confidence
                // will time out naturally.
                self?.recomputeConfidence()
            }
        }
    }

    private func sendArm() {
        guard let wm = workoutManager else { return }
        lastArmSentAt = Date()
        let payload: [String: String] = [
            "type": "linkArm",
            "ttl": String(Self.armTTL),
            "ts": String(lastArmSentAt.timeIntervalSince1970)
        ]
        wm.sendMirrorPayload(payload) { _ in }
    }

    private func sendDisarm() {
        guard let wm = workoutManager else { return }
        let payload: [String: String] = [
            "type": "linkDisarm",
            "ts": String(Date().timeIntervalSince1970)
        ]
        wm.sendMirrorPayload(payload) { _ in }
    }

    /// Phone responded to a heartbeat — channel is alive.
    func handleLinkPingAck(id _: UUID) {
        lastPingAckAt = Date()
        recomputeConfidence()
    }

    /// Phone confirmed AVAudioSession is active — speech will fire fast.
    func handleLinkArmAck(ts _: TimeInterval) {
        lastArmAckAt = Date()
        // An arm-ack is also implicitly a channel-roundtrip, so treat it as
        // a heartbeat — saves us waiting up to 5s for the next ping tick.
        lastPingAckAt = Date()
        recomputeConfidence()
    }

    /// Returns true when phone successfully acked AVAudioSession activation
    /// recently — used by VoiceNavigator to know that a primed send won't
    /// pay the activation handshake.
    var isAudioSessionPrimed: Bool {
        guard armRequested else { return false }
        return Date().timeIntervalSince(lastArmAckAt) < Self.primedWindow
    }

    /// Whether the AVAudioSession arm has been requested (and not yet
    /// disarmed). Used by VoiceNavigator to opportunistically synchronously
    /// arm on a `.warm` send.
    var isArmed: Bool { armRequested }

    private func recomputeConfidence() {
        let now = Date()
        let channelOK = now.timeIntervalSince(lastPingAckAt) < Self.warmWindow
        let armOK = armRequested && now.timeIntervalSince(lastArmAckAt) < Self.primedWindow

        let next: LinkConfidence
        if !channelOK {
            next = .none
        } else if armOK {
            next = .primed
        } else {
            next = .warm
        }

        if next != linkConfidence {
            log("confidence: \(linkConfidence) → \(next)")
            linkConfidence = next
        }
    }

    // MARK: Logging

    private func log(_ msg: String) {
        print("[VoiceLink] \(msg)")
    }

    private func format(_ v: Double) -> String {
        String(format: "%.1f", v)
    }
}

extension LinkConfidence: CustomStringConvertible {
    var description: String {
        switch self {
        case .none:   return "none"
        case .warm:   return "warm"
        case .primed: return "primed"
        }
    }
}
