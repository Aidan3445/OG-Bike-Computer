//
//  WorkoutManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Combine
import CoreLocation
import Foundation
import HealthKit
import UserNotifications
import WatchKit

/// Runs a ride on the watch. This file holds the ride's state and its
/// lifecycle (start, pause, resume, stop). The `WorkoutManager+` files in
/// this folder add the features, and the sub-services keep their own state.
class WorkoutManager: NSObject, ObservableObject {

    // MARK: - Published ride state

    @Published var isActive = false
    @Published var isPaused = false
    @Published var autoPauseState: AutoPauseState = .moving
    @Published var currentActivity: ActivityType = .cycling
    @Published var currentLocation: CLLocation?
    @Published var heading: Double = 0
    @Published var speed: Double = 0
    @Published var maxSpeed: Double = 0
    @Published var totalDistance: Double = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var movingTime: TimeInterval = 0
    @Published var heartRate: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var maxHeartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var currentElevation: Double = 0
    @Published var liveElevationGain: Double = 0
    @Published var liveElevationLoss: Double = 0
    @Published var highestElevation: Double = -Double.greatestFiniteMagnitude
    @Published var lowestElevation: Double = Double.greatestFiniteMagnitude
    @Published var currentGrade: Double = 0
    @Published var estimatedPower: Double = 0
    @Published var averagePower: Double = 0
    @Published var maxPower: Double = 0
    @Published var recordedLocations: [CLLocation] = []

    /// Set when a ride ends or is held, cleared when the summary is dismissed.
    @Published var completedRideSummary: WatchRideSummary?
    /// Asks whether to save to Apple Health when auto upload is off.
    @Published var showHealthKitPrompt = false
    /// Holding this ride would replace another held ride. The UI asks and
    /// answers through `resolveHoldConflict(_:)`.
    @Published var pendingHoldConflict = false
    /// A held ride rebuilt from a checkpoint after a crash.
    @Published var recoveredRideSummary: RideSummary?

    #if DEBUG
        @Published var isSimulating = false
    #else
        let isSimulating = false
    #endif

    var hasRoute: Bool { navigation.processedRoute != nil }
    var isAutoPaused: Bool { autoPauseState != .moving }
    var averageSpeed: Double { movingTime > 0 ? totalDistance / movingTime : 0 }
    var session: HKWorkoutSession? { healthKit.session }

    // MARK: - Settings

    var riderMass: Double = 75  // kg
    var bikeMass: Double = 10  // kg
    var totalMass: Double { riderMass + bikeMass }
    var healthKitAutoUpload: Bool = true

    var ridePreferences: RidePreferences = .default {
        didSet {
            let was = oldValue.autoPause
            let now = ridePreferences.autoPause
            guard isActive,
                was.mode != now.mode || was.speedThreshold != now.speedThreshold
            else { return }
            DiagnosticsLog.event(
                "Rules",
                "stop mode changed mode=\(now.mode.rawValue) pauseSpeed=\(Self.mph(now.speedThreshold))mph positionPause=\(Self.mph(positionPauseSpeed))mph"
            )
        }
    }

    var navigationAlerts: NavigationAlertPreferences = .default {
        didSet {
            let splitLength = navigationAlerts.splitAlerts.splitDistance
            guard isActive, splitLength != oldValue.splitAlerts.splitDistance else { return }
            splitTracker.reanchor(splitLength: splitLength, at: rideTotals)
        }
    }

    /// Called with true to save the workout to Apple Health, false to discard it.
    var healthKitPromptHandler: ((Bool) -> Void)?
    var onRideCompleted: ((RideSummary) -> Void)?
    weak var rideStore: RideStore?
    /// The sim track's heart rate for the point being replayed, if it has one.
    var simTrackHeartRate: Double?

    // MARK: - Sub-services

    let navigation = NavigationTracker()
    let healthKit = HealthKitRecorder()
    let locationManager = CLLocationManager()
    let battery = BatteryManager()
    let altimeter = AltimeterReader()
    let stopDetector = StopDetector()
    var departureDetector = DepartureDetector()
    var distanceTracker = DistanceTracker()
    var positionBuffer = PositionBuffer()
    var tentative = TentativeResumeBuffer()
    var elevationTracker = ElevationTracker()
    var gradeEstimator = GradeEstimator()
    var splitTracker = SplitTracker()
    var heartRateStat = RunningStat()
    var powerStat = RunningStat()
    var trace = RideTraceFiles()

    // MARK: - Ride

    private(set) var activeRoute: Route?
    /// A route loaded before the first fix anchors on that fix.
    var needsAnchor = false
    /// The route's name at ride start, kept through mid-ride route swaps.
    var initialRouteName: String?
    var currentRideID: UUID?
    /// The held ride being continued, until the new segment has started.
    var continuationBase: RideSummary?
    /// Split saved with a held ride, applied when the ride continues.
    var heldSplitProgress: SplitProgress?
    /// Calories from before a hold. Each workout session counts from zero.
    var caloriesBase: Double = 0
    var recordedHeartRates: [Double?] = []
    var recordedPowers: [Double?] = []

    // MARK: - Clock

    var timerStart: Date?
    var timerAccumulated: TimeInterval = 0
    var displayTimer: Timer?
    var workoutStartDate: Date?
    /// Set once when the ride first starts. Elapsed time counts from it, holds included.
    var initialRideStartDate: Date?

    /// Session states this device just asked for, so the delegate can tell
    /// them apart from changes made on the phone. They expire so a call that
    /// changed nothing can't hide the phone's next command.
    var expectedSessionStates: Set<HKWorkoutSessionState> = []
    var expectedSessionStatesAt = Date.distantPast

    // MARK: - Auto-pause

    var slowSampleCount = 0
    var resumeGraceUntil: Date = .distantPast
    var lastLocationUpdateAt: Date?
    var pauseProbeTimer: Timer?
    var isSilentProbe = false
    var probeStartedAt: Date?
    var probeDueAt: Date?

    // MARK: - Telemetry and mirroring

    /// True once mirroring to the phone has started, false after a failed send until the retry.
    var isMirroringReady = false
    var mirroringRetryWorkItem: DispatchWorkItem?
    var telemetryTimer: Timer?
    /// HealthKit can hold back the phone's mirrored session for about a
    /// minute after the previous ride, so telemetry also goes straight over
    /// WatchConnectivity until the phone says it has the session.
    var earlyTelemetrySessionID: String?
    var earlyTelemetryUntil = Date.distantPast
    var lastTelemetrySendAt: Date?
    var lastTelemetryResult = ""
    var skippedTelemetrySends = 0

    // MARK: - Checkpoints and trace

    var checkpointTimer: Timer?
    var lastCheckpointLocationCount = 0
    /// Last values auto-pause worked from, for the trace.
    var traceBufferSpeedMPH: Double = 0
    var traceBufferDisplacement: Double = 0
    var traceCLSpeedMPH: Double = 0
    var rejectedFixesSinceLast = 0
    var staleFixesSinceLast = 0

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func requestPermissions() {
        healthKit.requestAuthorization()
        locationManager.requestWhenInUseAuthorization()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    // MARK: - Start

    /// Starts a ride with a new workout session. A held ride can sit alongside
    /// it. The rider only chooses between them when holding this one.
    func start(activity: ActivityType) {
        currentActivity = activity
        do {
            try healthKit.makeSession(activity: activity, withBuilder: true, delegate: self)
        } catch {
            print("Failed to create workout session: \(error)")
            return
        }
        startMirroring(label: "start")
        healthKit.startActivity()
        healthKit.beginCollection()
        beginRide()
    }

    /// Setup shared by new and continued rides once the session exists.
    private func beginRide() {
        let isContinuation = continuationBase != nil
        healthKit.startRoute()
        startVoice()
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        if !isContinuation {
            liveElevationGain = 0
            liveElevationLoss = 0
        }
        elevationTracker.startBarometer(gain: liveElevationGain, loss: liveElevationLoss)
        startAltimeter()
        stopDetector.startPedometer()

        workoutStartDate = Date()
        timerStart = workoutStartDate
        // A continued ride keeps its elapsed time and calories.
        if !isContinuation {
            timerAccumulated = 0
            initialRideStartDate = workoutStartDate
            caloriesBase = 0
        }
        startDisplayTimer()

        isActive = true
        isPaused = false
        // The rider may have moved since the hold, so the gap from the held
        // track's end isn't ridden distance. Only a new ride waits to set off.
        resetMotion(
            anchor: isContinuation ? recordedLocations.last : nil,
            skipGap: isContinuation,
            awaitDeparture: !isContinuation)

        let splitLength = navigationAlerts.splitAlerts.splitDistance
        if isContinuation && splitLength > 0 {
            // Elapsed time hasn't ticked yet, so the held total stands in for it.
            var totals = rideTotals
            totals.elapsedTime = timerAccumulated
            splitTracker.restore(heldSplitProgress, splitLength: splitLength, at: totals)
            heldSplitProgress = nil
        } else {
            splitTracker.startNew(at: rideTotals)
        }
        initialRouteName = navigation.processedRoute?.name
        startTelemetryTimer()

        if !isContinuation {
            currentRideID = UUID()
            lastCheckpointLocationCount = 0
        }
        if let currentRideID { openTraceFiles(rideID: currentRideID) }
        startCheckpointTimer()
        continuationBase = nil
    }

    /// `VoiceNavigator.reset()` leaves it stopped and `configureAudioSession()`
    /// starts it again, so the order matters.
    func startVoice() {
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.configureAudioSession()
        VoiceNavigator.shared.workoutManager = self
        VoiceAlertTransport.shared.start()
    }

    /// Clears auto-pause, distance and departure state for a ride starting or continuing.
    func resetMotion(anchor: CLLocation?, skipGap: Bool, awaitDeparture: Bool) {
        autoPauseState = .moving
        slowSampleCount = 0
        positionBuffer.removeAll()
        lastLocationUpdateAt = nil
        distanceTracker.reset(anchor: anchor, skipNextGap: skipGap)
        stopDetector.resetRidingSpeed()
        departureDetector.reset(waiting: awaitDeparture)
    }

    // MARK: - Pause and resume

    func expectSessionStates(_ states: Set<HKWorkoutSessionState>) {
        expectedSessionStates = states
        expectedSessionStatesAt = Date()
    }

    /// Pauses the session and the moving clock. Elapsed time keeps ticking.
    func pauseSession() {
        expectSessionStates([.paused])
        healthKit.pause()
        markPaused()
    }

    func pause() {
        DiagnosticsLog.event("AutoPause", "manual pause while \(autoPauseState)")
        stopMotionForPause()
        pauseSession()
    }

    func resumeSession() {
        expectSessionStates([.running])
        healthKit.resume()
        markRunning()
        if isAutoPaused {
            autoPauseState = .moving
            tentative.clear()
        }
        // Drift while paused shouldn't book on the first reading back.
        elevationTracker.barometer.rebase()
    }

    func resume() {
        DiagnosticsLog.event("AutoPause", "manual resume while \(autoPauseState)")
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        lastLocationUpdateAt = nil
        restartMotion()
        resumeSession()
    }

    func markPaused() {
        stopClock()
        isPaused = true
    }

    func markRunning() {
        timerStart = Date()
        startDisplayTimer()
        isPaused = false
    }

    func stopClock() {
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
    }

    /// Stops GPS and any auto-pause in progress. A manual pause takes over from auto-pause.
    func stopMotionForPause() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        if autoPauseState == .tentativeResume {
            tentative.clear()
        }
        cancelPauseProbe()
        autoPauseState = .moving
    }

    /// Fresh auto-pause state after a manual pause. The paused stretch isn't ridden distance.
    func restartMotion() {
        distanceTracker.skipNextGap()
        slowSampleCount = 0
        positionBuffer.removeAll()
        cancelPauseProbe()
        autoPauseState = .moving
        resumeGraceUntil = Date().addingTimeInterval(5)
    }

    // MARK: - Stop

    func stop(save: Bool) {
        DiagnosticsLog.event("Mirroring", "stop save=\(save) sim=\(isSimulating)")
        stopRideServices()
        expectSessionStates([.stopped, .ended])
        stopClock()
        stopDisplayTimer()
        departureDetector.reset(waiting: false)
        settleTentativeResume()
        stopNavigationAndMirroring()

        // A discard reaches the phone before the session ends, so its Live
        // Activity shows the discarded banner and no "Waiting for ride" row.
        // Sim rides never save, so they always count as discarded.
        if !save || isSimulating {
            ConnectivityManager.shared.sendRideTerminalIntent("discarded")
        }
        if !isSimulating {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
            healthKit.end()
        }

        // The summary shows while the save runs.
        if save {
            completedRideSummary = makeWatchSummary(isHeld: false)
        }

        if save && !isSimulating {
            saveFinishedRide()
        } else {
            if isSimulating {
                healthKit.end()
            } else {
                healthKit.discardWorkout()
            }
            RideCheckpointStore.delete()
            cleanup()
        }
    }

    func discard() {
        stop(save: false)
    }

    /// Saves the workout to Apple Health, or asks first when auto upload is
    /// off, then sends the ride to the phone.
    private func saveFinishedRide() {
        print("[stop] saving ride, \(recordedLocations.count) recorded locations")
        healthKit.endSegment(at: Date()) { [weak self] segment in
            let finish: (Bool) -> Void = { saveToHealth in
                guard saveToHealth else {
                    segment.discard()
                    self?.exportAndTransferRide(savedToHealthKit: false)
                    self?.cleanup()
                    return
                }
                segment.save(waitForRoute: true) { saved in
                    self?.exportAndTransferRide(savedToHealthKit: saved)
                    self?.cleanup()
                }
            }
            guard let self else { return }
            if self.healthKitAutoUpload {
                finish(true)
            } else {
                self.healthKitPromptHandler = finish
                DispatchQueue.main.async { self.showHealthKitPrompt = true }
            }
        }
    }

    /// Stops everything that runs alongside a ride, for a stop or a hold.
    func stopRideServices() {
        closeTraceFiles()
        stopAltimeter()
        stopDetector.stopPedometer()
        stopCheckpointTimer()
        stopTelemetryTimer()
        healthKit.stopRouteTimer()
    }

    func stopNavigationAndMirroring() {
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.workoutManager = nil
        VoiceAlertTransport.shared.stop()
        navigation.reset()
        isMirroringReady = false
        mirroringRetryWorkItem?.cancel()
        mirroringRetryWorkItem = nil
    }

    func dismissSummary() {
        completedRideSummary = nil
        isActive = false
    }

    /// The summary keeps `isActive` true until it's dismissed, so phone
    /// commands clear it first or they'd see a ride that already ended.
    func dismissSummaryIfShowing() {
        if completedRideSummary != nil {
            dismissSummary()
        }
    }

    /// Resets everything for the next ride once this one has saved or been discarded.
    func cleanup() {
        DispatchQueue.main.async {
            // With a summary showing, dismissing it clears isActive.
            if self.completedRideSummary == nil {
                self.isActive = false
            }
            self.isPaused = false
            #if DEBUG
                self.isSimulating = false
            #endif
            self.isMirroringReady = false
            self.recordedLocations = []
            self.recordedHeartRates = []
            self.recordedPowers = []
            self.healthKit.clearPendingRoute()
            self.autoPauseState = .moving
            self.cancelPauseProbe()
            self.slowSampleCount = 0
            self.positionBuffer.removeAll()
            self.distanceTracker.reset(anchor: nil, skipNextGap: false)
            self.stopDetector.resetRidingSpeed()
            self.tentative.clear()
            self.speed = 0
            self.totalDistance = 0
            self.workoutStartDate = nil
            self.initialRideStartDate = nil
            self.elapsedTime = 0
            self.movingTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.currentLocation = nil
            self.maxSpeed = 0
            self.currentElevation = 0
            self.liveElevationGain = 0
            self.liveElevationLoss = 0
            self.highestElevation = -Double.greatestFiniteMagnitude
            self.lowestElevation = Double.greatestFiniteMagnitude
            self.currentGrade = 0
            self.estimatedPower = 0
            self.averagePower = 0
            self.maxPower = 0
            self.averageHeartRate = 0
            self.maxHeartRate = 0
            self.heartRateStat = RunningStat()
            self.powerStat = RunningStat()
            self.gradeEstimator.reset()
            self.elevationTracker.resetGPS()
            self.currentRideID = nil
            self.continuationBase = nil
        }
    }

    // MARK: - Display timer

    func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            DispatchQueue.main.async { self.tick() }
        }
    }

    func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    private func tick() {
        if let origin = initialRideStartDate {
            elapsedTime = Date().timeIntervalSince(origin)
        }
        // Before departure only Record All counts moving time.
        let waiting = departureDetector.isWaiting && !isRecordingEverything
        if !isAutoPaused && !isPaused && !isStandingStill && !waiting {
            movingTime += 1
        }
        tickAutoPauseFallback()
        traceTick()
    }

    // MARK: - Route

    func loadRoute(_ route: Route) {
        activeRoute = route
        navigation.load(RouteProcessor.process(route))
        // Anchor where the rider is so navigation doesn't start from the first segment.
        if let loc = currentLocation {
            navigation.anchorToLocation(loc)
            needsAnchor = false
        } else {
            needsAnchor = true
        }
    }

    func clearRoute() {
        activeRoute = nil
        navigation.reset()
        needsAnchor = false
        VoiceNavigator.shared.resetForRouteSwap()
    }
}
