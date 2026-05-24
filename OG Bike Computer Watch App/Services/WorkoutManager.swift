//
//  WorkoutManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import HealthKit
import CoreLocation
import Combine

import WatchKit
import UserNotifications

enum AutoPauseState {
    case moving
    case paused
    case tentativeResume
}

private struct CheckpointMeta: Codable, Sendable {
    let rideID: UUID
    let startDate: Date
    let name: String
    let activityType: ActivityType
    let distance: Double
    let movingTime: TimeInterval
    let elapsedTime: TimeInterval
    let calories: Double
    let elevationGain: Double
    let elevationLoss: Double
    let avgSpeed: Double
    let maxSpeed: Double
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let avgPower: Double?
    let maxPower: Double?
    let highestElevation: Double?
    let lowestElevation: Double?
    let pointCount: Int
}

private func decodeCheckpointMeta(_ data: Data) -> CheckpointMeta? {
    try? JSONDecoder().decode(CheckpointMeta.self, from: data)
}

class WorkoutManager: NSObject, ObservableObject {
    @Published var isActive = false
    @Published var isPaused = false
    @Published var heartRate: Double = 0
    @Published var activeCalories: Double = 0
    @Published var speed: Double = 0
    @Published var elapsedTime: TimeInterval = 0
    @Published var totalDistance: Double = 0
    @Published var heading: Double = 0
    @Published var currentLocation: CLLocation?
    @Published var currentActivity: ActivityType = .cycling
    var hasRoute: Bool { navigation.processedRoute != nil }
    private var needsAnchor = false

    /// Guards against the HK delegate double-handling local pause/resume/stop actions.
    /// Set true before local session control calls, reset in the delegate callback.
    private var isLocalStateChange = false

    // Extended metrics
    @Published var maxSpeed: Double = 0
    @Published var currentElevation: Double = 0
    @Published var liveElevationGain: Double = 0
    @Published var liveElevationLoss: Double = 0
    @Published var highestElevation: Double = -Double.greatestFiniteMagnitude
    @Published var lowestElevation: Double = Double.greatestFiniteMagnitude
    @Published var currentGrade: Double = 0
    @Published var estimatedPower: Double = 0
    @Published var averagePower: Double = 0
    @Published var maxPower: Double = 0
    @Published var averageHeartRate: Double = 0
    @Published var maxHeartRate: Double = 0

    // Grade + power computation state
    private var gradeWindowLocations: [CLLocation] = []
    private var gradeWindowDistance: Double { ridePreferences.elevationSmoothing.gradeWindowDistance }
    private var heartRateSum: Double = 0
    private var heartRateSampleCount: Int = 0
    private var powerSum: Double = 0
    private var powerSampleCount: Int = 0
    private var liveElevRefAltitude: Double?
    private var liveElevMinDelta: Double { ridePreferences.elevationSmoothing.elevMinDelta }

    // User-configurable mass for power estimate (synced from phone)
    var riderMass: Double = 75  // kg
    var bikeMass: Double = 10   // kg
    var totalMass: Double { riderMass + bikeMass }

    var ridePreferences: RidePreferences = .default
    var healthKitAutoUpload: Bool = true

    // Route name captured at ride start (survives mid-ride route swaps)
    private var initialRouteName: String?

    // Currently loaded route (nil for free ride)
    private(set) var activeRoute: Route?

    // Split tracking
    private var lastSplitDistance: Double = 0
    @Published var currentSplitNumber: Int = 0
    private var splitStartMovingTime: TimeInterval = 0
    private var splitStartElapsedTime: TimeInterval = 0
    private var splitStartDistance: Double = 0
    private var splitStartElevationGain: Double = 0
    private var splitStartElevationLoss: Double = 0
    private var splitStartCalories: Double = 0
    private var splitMaxSpeed: Double = 0
    private var splitMaxHR: Double = 0
    private var splitHRSum: Double = 0
    private var splitHRCount: Int = 0
    var navigationAlerts: NavigationAlertPreferences = .default {
        didSet {
            // When split distance changes mid-ride, reset accumulators so the next
            // split is measured from the current position with current stats.
            // Without this, changing e.g. 5mi → 0.5mi fires immediately using stale baselines.
            guard isActive,
                  navigationAlerts.splitAlerts.splitDistance != oldValue.splitAlerts.splitDistance else { return }
            lastSplitDistance = totalDistance
            resetSplitAccumulators()
        }
    }

    /// Snapshot the current cumulative ride state into the split-start baselines
    /// so the next split's stats are measured from this point.
    private func resetSplitAccumulators() {
        splitStartDistance = totalDistance
        splitStartMovingTime = movingTime
        splitStartElapsedTime = elapsedTime
        splitStartElevationGain = liveElevationGain
        splitStartElevationLoss = liveElevationLoss
        splitStartCalories = activeCalories
        splitMaxSpeed = 0
        splitMaxHR = 0
        splitHRSum = 0
        splitHRCount = 0
    }

    /// Set after ride ends, cleared when user dismisses summary screen
    @Published var completedRideSummary: WatchRideSummary?
    /// Set when healthKitAutoUpload is off — prompts the user to save or discard the HK workout
    @Published var showHealthKitPrompt = false
    /// Set when starting a new ride would discard an existing held ride.
    /// The watch UI should show a confirmation sheet and call the closure to proceed or nil to cancel.
    @Published var pendingStartConfirmation: (() -> Void)?
    /// Continuation called with `true` to save to HealthKit, `false` to discard
    var healthKitPromptHandler: ((Bool) -> Void)?

    var onRideCompleted: ((RideSummary) -> Void)?

    private var routeInsertionTimer: Timer?
    private var pendingRouteLocations: [CLLocation] = []
    @Published var recordedLocations: [CLLocation] = []
    private var recordedHeartRates: [Double?] = []
    private var recordedPowers: [Double?] = []

    private let healthStore = HKHealthStore()
    private(set) var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    // Tracks every in-flight insertRouteData call so finishRoute(with:) only
    // runs after they've all completed. Without this, periodic flushes can
    // still be in-flight when finishRoute fires, producing a HK workout with
    // a missing or partial route in the Fitness app.
    private let routeInsertGroup = DispatchGroup()

    private let locationManager = CLLocationManager()

    private var timerStart: Date?
    private var timerAccumulated: TimeInterval = 0
    private var displayTimer: Timer?
    private var workoutStartDate: Date?
    /// Set once at the very beginning of a ride (or restored from summary.date on continuation).
    /// Never reset mid-ride — elapsed time is always relative to this.
    private var initialRideStartDate: Date?

    let navigation = NavigationTracker()

    private let battery = BatteryManager()
    @Published var autoPauseState: AutoPauseState = .moving
    var isAutoPaused: Bool { autoPauseState != .moving }

    // Speed sampling
    private var slowSampleCount = 0
    private let slowSamplesForPause = 5
    private var resumeGraceUntil: Date = .distantPast

    // Tentative resume buffer
    private var tentativeLocations: [CLLocation] = []
    private var tentativeDistance: Double = 0
    private var tentativeStartTime: Date?
    private var fastSampleCount = 0
    private let fastSamplesForResume = 5
    private let minTentativeDuration: TimeInterval = 3.0

    // Gap-safe distance tracking
    private var lastCommittedLocation: CLLocation?
    private var skipNextDistanceGap = false
    
    @Published var movingTime: TimeInterval = 0

    // Telemetry for phone Live Activity
    private var telemetryTimer: Timer?

    // Checkpoint / crash recovery
    private var checkpointTimer: Timer?
    private var lastCheckpointLocationCount = 0
    private var currentRideID: UUID?
    private var continuationBase: RideSummary?
    @Published var recoveredRideSummary: RideSummary?

    weak var rideStore: RideStore?

    // Mirroring: set true after delay post-mirroring, false on error/disconnect.
    // Re-arms via DispatchWorkItem after 10s to detect phone reconnection.
    // Read-public so VoiceNavigator can route audio based on whether the
    // phone is reachable; writes stay internal to WorkoutManager.
    private(set) var isMirroringReady = false
    private var mirroringRetryWorkItem: DispatchWorkItem?

    // SIM — only available in debug builds
    #if DEBUG
    @Published var isSimulating = false

    func startSimulation(activity: ActivityType) {
        self.currentActivity = activity
        isSimulating = true

        let config = HKWorkoutConfiguration()
        config.activityType = activity.hkType
        config.locationType = .outdoor

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            session?.delegate = self
        } catch {
            print("[Sim] Failed to create workout session: \(error)")
        }

        isMirroringReady = false
        session?.startMirroringToCompanionDevice { [weak self] success, error in
            if let error = error {
                print("[Sim] Mirroring failed: \(error)")
            } else {
                print("[Sim] Mirroring started: \(success)")
                if success {
                    DispatchQueue.main.async {
                        self?.isMirroringReady = true
                        print("[Sim] Mirroring ready for speech routing")
                    }
                }
            }
        }

        session?.startActivity(with: Date())

        // reset() THEN configureAudioSession() — order matters!
        // reset() sets isStopped=true, configureAudioSession() sets it false
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.configureAudioSession()
        VoiceNavigator.shared.workoutManager = self
        VoiceAlertTransport.shared.start()

        workoutStartDate = Date()
        timerStart = workoutStartDate
        timerAccumulated = 0
        initialRideStartDate = workoutStartDate
        startDisplayTimer()

        isActive = true
        isPaused = false
        autoPauseState = .moving
        slowSampleCount = 0
        lastCommittedLocation = nil
        skipNextDistanceGap = false
        lastSplitDistance = 0
        currentSplitNumber = 0
        resetSplitAccumulators()
        initialRouteName = navigation.processedRoute?.name
        startTelemetryTimer()
    }
    #else
    let isSimulating = false
    #endif

    func processLocation(_ location: CLLocation) {
        DispatchQueue.main.async {
            self.currentLocation = location
            // CLLocation.speed can be stale or unreliable when stationary.
            // Reject readings with invalid speedAccuracy so they don't keep the
            // display pinned to an old value and block auto-pause from firing.
            if location.speedAccuracy < 0 {
                self.speed = 0
            } else {
                self.speed = max(location.speed, 0)
            }

            self.updateExtendedMetrics(location)

            // Navigation + voice only when a route is loaded
            if self.hasRoute {
                // Deferred anchor: if route was loaded before location was available
                if self.needsAnchor {
                    self.needsAnchor = false
                    self.navigation.anchorToLocation(location)
                }

                if let alert = self.navigation.update(location: location, riderDistance: self.totalDistance) {
                    self.handleTurnAlert(alert)
                }
                VoiceNavigator.shared.update(
                    nav: self.navigation,
                    speed: self.speed,
                    heading: self.heading,
                    isActivelyMoving: self.autoPauseState == .moving)
            }

            // Accumulate distance in simulation mode too
            if self.isSimulating {
                self.accumulateDistance(location)
                self.checkSplit()
                return
            }

            self.updateAutoPause()

            // While auto-paused, force the displayed speed to 0 regardless of
            // what GPS reports — stale/noisy CL readings shouldn't show motion
            // when the rider is stopped.
            if self.autoPauseState == .paused {
                self.speed = 0
            }

            // Recording + distance based on auto-pause state
            switch self.autoPauseState {
            case .moving:
                self.accumulateDistance(location)
                self.checkSplit()
                self.recordedLocations.append(location)
                self.recordedHeartRates.append(self.heartRate > 0 ? self.heartRate : nil)
                self.recordedPowers.append(self.estimatedPower > 0 ? self.estimatedPower : nil)
                self.pendingRouteLocations.append(location)

            case .paused:
                // No recording, no distance
                break

            case .tentativeResume:
                // Stage in buffer — distance tracked internally
                if let prev = self.tentativeLocations.last {
                    self.tentativeDistance += location.distance(from: prev)
                }
                self.tentativeLocations.append(location)
            }

            // Battery management (consolidated — runs for both route and free rides)
            let mode = self.battery.recommendedMode(
                distanceToNextTurn: self.navigation.distanceToNextTurn,
                isOffRoute: self.navigation.isOffRoute,
                speed: self.speed,
                floor: self.ridePreferences.gpsAccuracyFloor,
                dynamicOptimization: self.ridePreferences.dynamicGPSOptimization)
            self.battery.apply(mode: mode, to: self.locationManager)
        }
    }
    // END SIM

    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.activityType = .fitness
    }

    func requestPermissions() {
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKSeriesType.workoutRoute()
        ]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceCycling)
        ]

        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("HealthKit auth error: \(error)")
            }
        }

        locationManager.requestWhenInUseAuthorization()

        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    private func flushRouteLocations() {
        guard !pendingRouteLocations.isEmpty else { return }
        guard let routeBuilder = routeBuilder else {
            pendingRouteLocations = []
            return
        }
        let batch = pendingRouteLocations
        pendingRouteLocations = []

        routeInsertGroup.enter()
        routeBuilder.insertRouteData(batch) { [weak self] _, error in
            if let error = error {
                print("Route insert error: \(error)")
            }
            self?.routeInsertGroup.leave()
        }
    }
    
    
    private func accumulateDistance(_ location: CLLocation) {
        if skipNextDistanceGap {
            skipNextDistanceGap = false
            lastCommittedLocation = location
            return
        }
        if let prev = lastCommittedLocation {
            totalDistance += location.distance(from: prev)
        }
        lastCommittedLocation = location
    }

    private func checkSplit() {
        let splitPrefs = navigationAlerts.splitAlerts
        guard splitPrefs.enabled else { return }
        let splitDist = splitPrefs.splitDistance
        guard totalDistance - lastSplitDistance >= splitDist else { return }

        currentSplitNumber += 1
        lastSplitDistance += splitDist

        // Compute split-specific stats
        let splitMovingTime = movingTime - splitStartMovingTime
        let splitDistance = totalDistance - splitStartDistance
        let splitAvgSpeed = splitMovingTime > 0 ? splitDistance / splitMovingTime : 0
        let splitAvgHR = splitHRCount > 0 ? splitHRSum / Double(splitHRCount) : 0

        let splitStats = SplitStats(
            movingTime: splitMovingTime,
            elapsedTime: elapsedTime - splitStartElapsedTime,
            distance: splitDistance,
            averageSpeed: splitAvgSpeed,
            maxSpeed: splitMaxSpeed,
            averageHeartRate: splitAvgHR,
            maxHeartRate: splitMaxHR,
            elevationGain: max(0, liveElevationGain - splitStartElevationGain),
            elevationLoss: max(0, liveElevationLoss - splitStartElevationLoss),
            calories: max(0, activeCalories - splitStartCalories)
        )

        VoiceNavigator.shared.announceSplit(
            number: currentSplitNumber,
            splitDistance: splitDist,
            splitStats: splitStats,
            rideStats: currentRideStats(),
            metrics: splitPrefs.metrics,
            mode: splitPrefs.mode
        )

        resetSplitAccumulators()
    }

    func currentRideStats() -> SplitStats {
        SplitStats(
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            distance: totalDistance,
            averageSpeed: movingTime > 0 ? totalDistance / movingTime : 0,
            maxSpeed: maxSpeed,
            averageHeartRate: heartRateSampleCount > 0 ? averageHeartRate : 0,
            maxHeartRate: maxHeartRate,
            elevationGain: liveElevationGain,
            elevationLoss: liveElevationLoss,
            calories: activeCalories
        )
    }

    private func commitTentativeBuffer() {
        // Add only the internal distance of the buffer (no gap bridging)
        totalDistance += tentativeDistance

        // Move staged locations into the real recording
        recordedLocations.append(contentsOf: tentativeLocations)
        // Backfill HR/power for tentative locations (use current values)
        for _ in tentativeLocations {
            recordedHeartRates.append(heartRate > 0 ? heartRate : nil)
            recordedPowers.append(estimatedPower > 0 ? estimatedPower : nil)
        }
        pendingRouteLocations.append(contentsOf: tentativeLocations)

        // Retroactively credit the tentative period as moving time
        if let start = tentativeStartTime {
            movingTime += Date().timeIntervalSince(start)
        }

        if let last = tentativeLocations.last {
            lastCommittedLocation = last
        }

        clearTentativeBuffer()
    }

    private func discardTentativeBuffer() {
        clearTentativeBuffer()
    }

    private func clearTentativeBuffer() {
        tentativeLocations = []
        tentativeDistance = 0
        tentativeStartTime = nil
        fastSampleCount = 0
    }

    private func startRouteInsertion() {
        routeInsertionTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            self?.flushRouteLocations()
        }
    }

    /// Start a ride by creating a new local HKWorkoutSession (default path).
    func start(activity: ActivityType) {
        // Discard any existing held ride (caller must have already confirmed with user)
        if continuationBase == nil {
            autoFinalizeHeldRideIfNeeded()
        }

        let config = HKWorkoutConfiguration()
        config.activityType = activity.hkType
        config.locationType = .outdoor

        self.currentActivity = activity

        do {
            session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
            builder = session?.associatedWorkoutBuilder()
        } catch {
            print("Failed to create workout session: \(error)")
            return
        }

        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore,
            workoutConfiguration: config)

        session?.delegate = self
        builder?.delegate = self

        // Watch-initiated ride → mirror to phone for telemetry/speech
        isMirroringReady = false
        session?.startMirroringToCompanionDevice { [weak self] success, error in
            print("[Mirroring] Start mirroring result: success=\(success), error=\(String(describing: error))")
            if success {
                DispatchQueue.main.async {
                    // Mirroring is what launches and keeps the phone app alive.
                    // Once startMirroringToCompanionDevice's callback fires
                    // success=true, WCSession.isReachable will become true
                    // shortly after and stay true for the duration of the
                    // ride. The plan's transport layer (VoiceAlertTransport)
                    // is what actually decides phone vs watch per-alert.
                    self?.isMirroringReady = true
                    print("[Mirroring] Ready for speech routing")
                }
            }
        }

        session?.startActivity(with: Date())
        builder?.beginCollection(withStart: Date()) { success, error in
            if let error = error {
                print("Failed to begin collection: \(error)")
            }
        }

        beginRideCommon()
    }

    /// Shared setup after session creation — location, timers, voice nav, state reset.
    private func beginRideCommon() {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        startRouteInsertion()

        // reset() THEN configureAudioSession() — order matters!
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.configureAudioSession()
        VoiceNavigator.shared.workoutManager = self
        // Arm the WCSession alert transport for this ride. Snapshots
        // companion-app-installed at this moment + listens for didStart
        // acks coming back from the phone.
        VoiceAlertTransport.shared.start()

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        workoutStartDate = Date()
        timerStart = workoutStartDate
        // When continuing a held ride, timerAccumulated is pre-seeded; don't zero it
        if continuationBase == nil {
            timerAccumulated = 0
            initialRideStartDate = workoutStartDate
        }
        startDisplayTimer()

        isActive = true
        isPaused = false
        autoPauseState = .moving
        slowSampleCount = 0
        // Seed lastCommittedLocation from restored track end when continuing
        lastCommittedLocation = continuationBase != nil ? recordedLocations.last : nil
        skipNextDistanceGap = false
        // Split tracking anchors to current accumulated distance when continuing.
        // When resuming a held ride, restore the split number and last-split boundary
        // so numbering and timing carry over correctly (e.g. 12 mi in at 5mi splits → split 3 fires at 15mi).
        let splitDist = navigationAlerts.splitAlerts.splitDistance
        if continuationBase != nil && splitDist > 0 {
            currentSplitNumber = Int(totalDistance / splitDist)
            lastSplitDistance = Double(currentSplitNumber) * splitDist
        } else {
            currentSplitNumber = 0
            lastSplitDistance = totalDistance
        }
        resetSplitAccumulators()
        initialRouteName = navigation.processedRoute?.name
        startTelemetryTimer()

        // Only assign a fresh ride ID and reset checkpoint counter when NOT continuing a held ride
        if continuationBase == nil {
            currentRideID = UUID()
            lastCheckpointLocationCount = 0
        }
        startCheckpointTimer()
        continuationBase = nil  // clear after use
    }

    func pauseSession() {
        isLocalStateChange = true
        session?.pause()
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
        // Don't stop display timer — elapsed time should keep ticking while paused
        isPaused = true
    }

    func pause() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        // If tentative resume was in progress, discard it
        if autoPauseState == .tentativeResume {
            discardTentativeBuffer()
        }
        autoPauseState = .moving // manual pause resets auto-pause state
        pauseSession()
    }
    
    func resumeSession() {
        isLocalStateChange = true
        session?.resume()
        timerStart = Date()
        startDisplayTimer()
        isPaused = false
        if isAutoPaused {
            autoPauseState = .moving
            clearTentativeBuffer()
        }
    }

    func resume() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        // Skip the distance gap from pause period
        skipNextDistanceGap = true
        slowSampleCount = 0
        autoPauseState = .moving
        resumeGraceUntil = Date().addingTimeInterval(5)
        resumeSession()
    }

    private func updateAutoPause() {
        guard ridePreferences.autoPause.enabled else {
            if autoPauseState == .paused || autoPauseState == .tentativeResume {
                if autoPauseState == .tentativeResume {
                    commitTentativeBuffer()
                }
                resumeSession()
                autoPauseState = .moving
            }
            return
        }

        let speedMPH = speed * 2.23694
        let pauseThreshold = ridePreferences.autoPause.speedThreshold * 2.23694
        let resumeThreshold = pauseThreshold + 1.0

        switch autoPauseState {
        case .moving:
            guard Date() >= resumeGraceUntil else { return }

            if speedMPH < pauseThreshold {
                slowSampleCount += 1
            } else {
                slowSampleCount = 0
            }

            if slowSampleCount >= slowSamplesForPause && !isPaused {
                autoPauseState = .paused
                pauseSession()
                slowSampleCount = 0
                if navigationAlerts.autoPauseAlerts.enabled {
                    VoiceNavigator.shared.announceAutoPause(mode: navigationAlerts.autoPauseAlerts.pauseMode)
                }
            }

        case .paused:
            if speedMPH >= resumeThreshold {
                // Don't resume HK session yet — just start staging
                autoPauseState = .tentativeResume
                tentativeStartTime = Date()
                tentativeLocations = []
                tentativeDistance = 0
                fastSampleCount = 1

                // Seed buffer with current location
                if let loc = currentLocation {
                    tentativeLocations.append(loc)
                }
            }

        case .tentativeResume:
            if speedMPH >= resumeThreshold {
                fastSampleCount += 1

                let elapsed = tentativeStartTime
                    .map { Date().timeIntervalSince($0) } ?? 0

                if fastSampleCount >= fastSamplesForResume,
                   elapsed >= minTentativeDuration {
                    // Confirmed real movement — commit and go live
                    commitTentativeBuffer()
                    resumeSession()
                    autoPauseState = .moving
                    if navigationAlerts.autoPauseAlerts.enabled {
                        VoiceNavigator.shared.announceAutoResume(mode: navigationAlerts.autoPauseAlerts.resumeMode)
                    }
                }
            } else {
                // False alarm — discard buffer, stay paused
                discardTentativeBuffer()
                autoPauseState = .paused
                // HK session was never resumed, so no need to re-pause it
            }
        }
    }
    
    func setHeadingUpdates(enabled: Bool) {
        if enabled {
            locationManager.startUpdatingHeading()
        } else {
            locationManager.stopUpdatingHeading()
        }
    }

    func stop(save: Bool) {
        isLocalStateChange = true
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
        stopDisplayTimer()
        stopTelemetryTimer()
        stopCheckpointTimer()
        routeInsertionTimer?.invalidate()
        routeInsertionTimer = nil
        
        if autoPauseState == .tentativeResume {
            commitTentativeBuffer()
        }

        // Kill voice and navigation IMMEDIATELY
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.workoutManager = nil
        VoiceAlertTransport.shared.stop()
        navigation.reset()

        isMirroringReady = false
        mirroringRetryWorkItem?.cancel()
        mirroringRetryWorkItem = nil

        if !isSimulating {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
            session?.end()
        }

        // Capture summary immediately so the UI can show it while async processing runs
        if save {
            let avgSpd = movingTime > 0 ? totalDistance / movingTime : 0
            completedRideSummary = WatchRideSummary(
                distance: totalDistance,
                movingTime: movingTime,
                elapsedTime: elapsedTime,
                avgSpeed: avgSpd,
                maxSpeed: maxSpeed,
                elevationGain: liveElevationGain,
                calories: activeCalories,
                avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : 0,
                maxHeartRate: maxHeartRate > 0 ? maxHeartRate : 0,
                avgPower: powerSampleCount > 0 ? averagePower : 0,
                maxPower: maxPower > 0 ? maxPower : 0
            )
        }

        if save && !isSimulating {
            let finalBatch = pendingRouteLocations
            pendingRouteLocations = []
            let endDate = Date()

            print("[stop] saving ride, \(recordedLocations.count) recorded locations")

            // Capture this segment's builders so they survive a later session
            // creation reassigning self.builder/self.routeBuilder before the
            // async notify fires.
            let pendingBuilder = builder
            let pendingRouteBuilder = routeBuilder

            if !finalBatch.isEmpty, let pendingRouteBuilder {
                routeInsertGroup.enter()
                pendingRouteBuilder.insertRouteData(finalBatch) { [weak self] _, error in
                    if let error = error {
                        print("[stop] final route insert error: \(error)")
                    }
                    self?.routeInsertGroup.leave()
                }
            }

            // Wait for all in-flight inserts (timer flushes + final batch) so
            // the workout's route is complete before we attach it.
            routeInsertGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                print("[stop] endCollection")

                pendingBuilder?.endCollection(withEnd: endDate) { success, error in
                    if let error = error {
                        print("[stop] end collection error: \(error)")
                    }

                    let finishHealthKit = { [weak self] in
                        guard let self = self else { return }
                        pendingBuilder?.finishWorkout { [weak self] workout, error in
                            guard let self = self, let workout = workout else {
                                print("[stop] finish workout error: \(String(describing: error))")
                                self?.exportAndTransferRide(savedToHealthKit: false)
                                self?.cleanup()
                                return
                            }

                            print("[stop] workout saved, attaching route...")

                            pendingRouteBuilder?.finishRoute(with: workout, metadata: nil) { route, error in
                                if let error = error {
                                    print("[stop] finish route error: \(error)")
                                } else {
                                    print("[stop] route attached successfully")
                                }
                                self.exportAndTransferRide(savedToHealthKit: true)
                                self.cleanup()
                            }
                        }
                    }

                    let discardHealthKit = { [weak self] in
                        guard let self = self else { return }
                        print("[stop] discarding HealthKit workout")
                        pendingBuilder?.discardWorkout()
                        self.exportAndTransferRide(savedToHealthKit: false)
                        self.cleanup()
                    }

                    if self.healthKitAutoUpload {
                        finishHealthKit()
                    } else {
                        // Prompt user whether to save to Apple Health
                        self.healthKitPromptHandler = { saveToHealth in
                            if saveToHealth {
                                finishHealthKit()
                            } else {
                                discardHealthKit()
                            }
                        }
                        DispatchQueue.main.async {
                            self.showHealthKitPrompt = true
                        }
                    }
                }
            }
        } else {
            if isSimulating {
                session?.end()
            } else {
                builder?.discardWorkout()
            }
            deleteCheckpointFiles()
            cleanup()
        }
    }

    /// Dismiss the post-ride summary and return to route list
    func dismissSummary() {
        completedRideSummary = nil
        isActive = false
    }

    private func cleanup() {
        DispatchQueue.main.async {
            // Don't set isActive = false here — summary screen handles that via dismissSummary()
            // If no summary (discard), set isActive = false directly
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
            self.pendingRouteLocations = []
            self.autoPauseState = .moving
            self.slowSampleCount = 0
            self.lastCommittedLocation = nil
            self.skipNextDistanceGap = false
            self.clearTentativeBuffer()
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
            self.heartRateSum = 0
            self.heartRateSampleCount = 0
            self.powerSum = 0
            self.powerSampleCount = 0
            self.gradeWindowLocations = []
            self.liveElevRefAltitude = nil
            self.currentRideID = nil
            self.continuationBase = nil
        }
    }

    func discard() {
        stop(save: false)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self else { return }
            DispatchQueue.main.async {
                // Elapsed time always counts from the very first start of this ride
                if let origin = self.initialRideStartDate {
                    self.elapsedTime = Date().timeIntervalSince(origin)
                }
                // Moving time only ticks while not paused
                if !self.isAutoPaused && !self.isPaused {
                    self.movingTime += 1
                }
            }
        }
    }

    private func stopDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = nil
    }

    var averageSpeed: Double {
        movingTime > 0 ? totalDistance / movingTime : 0
    }

    private func updateExtendedMetrics(_ location: CLLocation) {
        // Max speed
        let spd = max(location.speed, 0)
        if spd > maxSpeed { maxSpeed = spd }
        if spd > splitMaxSpeed { splitMaxSpeed = spd }

        // Elevation (only if valid vertical accuracy)
        if location.verticalAccuracy >= 0 {
            let alt = location.altitude
            currentElevation = alt
            if alt > highestElevation { highestElevation = alt }
            if alt < lowestElevation { lowestElevation = alt }

            // Live elevation gain/loss with noise filtering
            if let ref = liveElevRefAltitude {
                let delta = alt - ref
                if delta > liveElevMinDelta {
                    liveElevationGain += delta
                    liveElevRefAltitude = alt
                } else if delta < -liveElevMinDelta {
                    liveElevationLoss -= delta
                    liveElevRefAltitude = alt
                }
            } else {
                liveElevRefAltitude = alt
            }
        }

        // Grade calculation: prefer route GPX elevation when on-route, fall back to GPS
        let routeGrade = computeRouteGrade()
        if let rg = routeGrade {
            // Smooth toward route-derived grade to avoid jumps
            let alpha = ridePreferences.elevationSmoothing.routeGradeAlpha
            currentGrade = currentGrade * (1 - alpha) + rg * alpha
        } else {
            // Fall back to GPS altitude sliding window
            gradeWindowLocations.append(location)

            // Trim window to keep only recent points spanning ~gradeWindowDistance
            while gradeWindowLocations.count > 2 {
                let oldest = gradeWindowLocations[0]
                let horizDist = horizontalDistance(from: oldest, to: location)
                if horizDist > gradeWindowDistance * 2 {
                    gradeWindowLocations.removeFirst()
                } else {
                    break
                }
            }

            if gradeWindowLocations.count >= 2,
               location.verticalAccuracy >= 0,
               location.verticalAccuracy < 20 { // Only use good GPS altitude
                let first = gradeWindowLocations[0]
                guard first.verticalAccuracy >= 0, first.verticalAccuracy < 20 else { return }
                let horizDist = horizontalDistance(from: first, to: location)
                if horizDist > 10 { // Need at least 10m horizontal to compute grade
                    let elevChange = location.altitude - first.altitude
                    let rawGrade = (elevChange / horizDist) * 100
                    // Smooth and clamp: steepest paved road is ~35%
                    let clampedGrade = max(-45, min(45, rawGrade))
                    let alpha = ridePreferences.elevationSmoothing.gpsGradeAlpha
                    currentGrade = currentGrade * (1 - alpha) + clampedGrade * alpha
                }
            }
        }

        // Power estimate (cycling physics model)
        // P = (Fg + Fr + Fa) * v
        if spd > 0.5 { // Only estimate when moving
            let mass = totalMass
            let g: Double = 9.81
            let crr: Double = 0.005 // rolling resistance
            let cdA: Double = 0.4 // drag area m^2
            let rho: Double = 1.225 // air density kg/m^3

            let gradeRad = atan(currentGrade / 100)
            let fg = mass * g * sin(gradeRad)
            let fr = crr * mass * g * cos(gradeRad)
            let fa = 0.5 * cdA * rho * spd * spd

            let power = max(0, (fg + fr + fa) * spd)
            estimatedPower = power
            if power > maxPower { maxPower = power }
            powerSum += power
            powerSampleCount += 1
            averagePower = powerSum / Double(powerSampleCount)
        } else {
            estimatedPower = 0
        }
    }

    private func horizontalDistance(from a: CLLocation, to b: CLLocation) -> Double {
        let flatA = CLLocation(latitude: a.coordinate.latitude, longitude: a.coordinate.longitude)
        let flatB = CLLocation(latitude: b.coordinate.latitude, longitude: b.coordinate.longitude)
        return flatA.distance(from: flatB)
    }

    /// Compute grade from GPX route elevation data when on-route.
    /// Uses a ~50m window of route points around the current position.
    private func computeRouteGrade() -> Double? {
        guard let route = navigation.processedRoute,
              !navigation.isOffRoute else { return nil }

        let points = route.points
        let segIdx = navigation.currentSegmentIndex
        guard segIdx < points.count else { return nil }

        // Find points ~25m behind and ~25m ahead along the route
        let currentDist = navigation.distanceAlongRoute
        let lookback: Double = 25
        let lookahead: Double = 25

        var behindIdx = segIdx
        while behindIdx > 0 && (currentDist - points[behindIdx].distanceFromStart) < lookback {
            behindIdx -= 1
        }
        var aheadIdx = segIdx
        while aheadIdx < points.count - 1 && (points[aheadIdx].distanceFromStart - currentDist) < lookahead {
            aheadIdx += 1
        }

        guard let elevBehind = points[behindIdx].elevation,
              let elevAhead = points[aheadIdx].elevation else { return nil }

        let horizDist = points[aheadIdx].distanceFromStart - points[behindIdx].distanceFromStart
        guard horizDist > 10 else { return nil }

        let grade = ((elevAhead - elevBehind) / horizDist) * 100
        return max(-45, min(45, grade))
    }

    func loadRoute(_ route: Route) {
        activeRoute = route
        let processed = RouteProcessor.process(route)
        navigation.load(processed)

        // Anchor to current position so we don't start at segment 0
        if let loc = currentLocation {
            navigation.anchorToLocation(loc)
            needsAnchor = false
        } else {
            // Defer anchoring until the first location update arrives
            needsAnchor = true
        }
    }

    func clearRoute() {
        activeRoute = nil
        navigation.reset()
        needsAnchor = false
        VoiceNavigator.shared.resetForRouteSwap()
    }

    private func handleTurnAlert(_ alert: NavigationTracker.TurnAlert) {
        let prefs = VoiceNavigator.shared.preferences
        let intensity = prefs.haptics.intensity

        switch alert {
        case .warning(_):
            let mode = prefs.turnAlerts.resolvedPrimaryApproachMode()
            guard mode.includesHaptic else { return }
            playHaptic(.click, intensity: intensity)
        case .imminent(let turn):
            let mode = prefs.turnAlerts.resolvedAtTurnMode()
            guard mode.includesHaptic else { return }
            let haptic: WKHapticType = {
                switch turn.direction {
                case .left, .slightLeft, .sharpLeft: return .directionDown
                case .right, .slightRight, .sharpRight: return .directionUp
                case .uTurn: return .failure
                case .straight: return .success
                }
            }()
            playHaptic(haptic, intensity: intensity)
        }
    }

    private func playHaptic(_ type: WKHapticType, intensity: HapticIntensity) {
        let device = WKInterfaceDevice.current()
        switch intensity {
        case .light:
            device.play(.click)
        case .medium:
            device.play(type)
        case .strong:
            device.play(type)
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                device.play(type)
            }
        }
    }

    private func exportAndTransferRide(savedToHealthKit: Bool = false) {
        let rideName: String
        if let routeName = initialRouteName {
            rideName = routeName
        } else {
            // Free ride — use time-of-day
            let hour = Calendar.current.component(.hour, from: Date())
            switch hour {
            case 5..<12:  rideName = "Morning Ride"
            case 12..<17: rideName = "Afternoon Ride"
            case 17..<21: rideName = "Evening Ride"
            default:      rideName = "Night Ride"
            }
        }

        let activity = currentActivity

        let avgSpeed = movingTime > 0 ? totalDistance / movingTime : 0
        var elevGain: Double = 0
        var elevLoss: Double = 0
        if recordedLocations.count > 1 {
            // Minimum altitude change (meters) to count — filters GPS noise.
            // CLLocation vertical accuracy is typically ±5-10m.
            let minDelta: Double = 4.0

            // Use a rolling reference altitude that only advances when
            // the cumulative change exceeds the threshold. This avoids
            // both spike noise and the problem of many small real changes
            // getting individually filtered out.
            var refAltitude = recordedLocations[0].altitude

            for i in 1..<recordedLocations.count {
                let alt = recordedLocations[i].altitude

                // Skip points with invalid/unknown altitude
                guard recordedLocations[i].verticalAccuracy >= 0 else { continue }

                let delta = alt - refAltitude
                if delta > minDelta {
                    elevGain += delta
                    refAltitude = alt
                } else if delta < -minDelta {
                    elevLoss -= delta
                    refAltitude = alt
                }
                // If within ±minDelta, don't move the reference —
                // lets real gradual climbs accumulate until they
                // cross the threshold.
            }
        }

        var locationsToSave = recordedLocations
        var hrsToSave = recordedHeartRates
        var powersToSave = recordedPowers
        if ridePreferences.ridePrivacy == .trimStartEnd {
            let trimDist = ridePreferences.ridePrivacy.trimDistance
            let (trimmed, startTrim, endTrim) = trimStartEndWithCounts(locationsToSave, trimDistance: trimDist)
            locationsToSave = trimmed
            hrsToSave = Array(hrsToSave.dropFirst(startTrim).dropLast(endTrim))
            powersToSave = Array(powersToSave.dropFirst(startTrim).dropLast(endTrim))
        }

        let trackData = TrackEncoder.encodeV5(locationsToSave, heartRates: hrsToSave, powers: powersToSave)
        let rideID = currentRideID ?? UUID()
        let trackFilename = "\(rideID.uuidString).track"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(trackFilename)

        do {
            try trackData.write(to: tempURL)
        } catch {
            print("Failed to write track data: \(error)")
            return
        }

        var summary = RideSummary(
            id: rideID,
            name: rideName,
            activityType: activity,
            date: Date(),
            elapsedTime: elapsedTime,
            movingTime: movingTime,
            distance: totalDistance,
            calories: activeCalories,
            elevationGain: elevGain,
            elevationLoss: elevLoss,
            avgSpeed: avgSpeed,
            pointCount: locationsToSave.count,
            trackFilename: trackFilename,
            maxSpeed: maxSpeed > 0 ? maxSpeed : nil,
            avgPower: powerSampleCount > 0 ? averagePower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
            highestElevation: highestElevation > -Double.greatestFiniteMagnitude ? highestElevation : nil,
            lowestElevation: lowestElevation < Double.greatestFiniteMagnitude ? lowestElevation : nil)

        // If HealthKit workout was saved, mark it in the upload records
        if savedToHealthKit {
            let fitnessRecord = ServiceUploadRecord(
                service: .fitness,
                remoteID: "healthkit",
                uploadedAt: Date(),
                webURL: nil
            )
            summary.uploads = [fitnessRecord]
        }

        DispatchQueue.main.async {
            self.onRideCompleted?(summary)
            ConnectivityManager.shared.sendRide(summary: summary, trackURL: tempURL)
            self.deleteCheckpointFiles()
        }
    }

    // MARK: - Ride Privacy

    private func trimStartEnd(_ locations: [CLLocation], trimDistance: Double) -> [CLLocation] {
        guard locations.count > 2 else { return locations }

        // Find start trim index
        var startIdx = 0
        var dist: Double = 0
        for i in 1..<locations.count {
            dist += locations[i].distance(from: locations[i - 1])
            if dist >= trimDistance {
                startIdx = i
                break
            }
        }

        // Find end trim index
        var endIdx = locations.count - 1
        dist = 0
        for i in stride(from: locations.count - 1, through: 1, by: -1) {
            dist += locations[i].distance(from: locations[i - 1])
            if dist >= trimDistance {
                endIdx = i
                break
            }
        }

        guard startIdx < endIdx else { return [] }
        return Array(locations[startIdx...endIdx])
    }

    /// Trim variant that returns the number of points removed from each end
    private func trimStartEndWithCounts(_ locations: [CLLocation], trimDistance: Double) -> ([CLLocation], Int, Int) {
        guard locations.count > 2 else { return (locations, 0, 0) }

        var startIdx = 0
        var dist: Double = 0
        for i in 1..<locations.count {
            dist += locations[i].distance(from: locations[i - 1])
            if dist >= trimDistance { startIdx = i; break }
        }

        var endIdx = locations.count - 1
        dist = 0
        for i in stride(from: locations.count - 1, through: 1, by: -1) {
            dist += locations[i].distance(from: locations[i - 1])
            if dist >= trimDistance { endIdx = i; break }
        }

        guard startIdx < endIdx else { return ([], locations.count, 0) }
        let endTrim = locations.count - 1 - endIdx
        return (Array(locations[startIdx...endIdx]), startIdx, endTrim)
    }

    // MARK: - Telemetry (Phone Live Activity)

    private func startTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = Timer.scheduledTimer(withTimeInterval: ridePreferences.telemetryRate.interval, repeats: true) { [weak self] _ in
            self?.sendTelemetry()
        }
    }

    private func stopTelemetryTimer() {
        telemetryTimer?.invalidate()
        telemetryTimer = nil
    }

    // MARK: - Checkpoint (Crash Recovery)

    private var checkpointTrackURL: URL {
        ConnectivityManager.ridesDirectory.appendingPathComponent("checkpoint.track")
    }
    private var checkpointMetaURL: URL {
        ConnectivityManager.ridesDirectory.appendingPathComponent("checkpoint.json")
    }

    private func startCheckpointTimer() {
        checkpointTimer?.invalidate()
        guard let interval = ridePreferences.checkpointInterval.interval else { return }
        checkpointTimer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { [weak self] _ in
            self?.saveCheckpoint()
        }
    }

    private func stopCheckpointTimer() {
        checkpointTimer?.invalidate()
        checkpointTimer = nil
    }

    private func saveCheckpoint() {
        guard isActive, !isPaused, autoPauseState == .moving else { return }
        let currentCount = recordedLocations.count
        guard currentCount > lastCheckpointLocationCount, currentCount > 0 else { return }

        let locations = recordedLocations
        let heartRates = recordedHeartRates
        let powers = recordedPowers
        let rideID = currentRideID ?? UUID()

        let rideName = currentRideName()
        let meta = CheckpointMeta(
            rideID: rideID,
            startDate: workoutStartDate ?? Date(),
            name: rideName,
            activityType: currentActivity,
            distance: totalDistance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            calories: activeCalories,
            elevationGain: liveElevationGain,
            elevationLoss: liveElevationLoss,
            avgSpeed: movingTime > 0 ? totalDistance / movingTime : 0,
            maxSpeed: maxSpeed,
            avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
            avgPower: powerSampleCount > 0 ? averagePower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            highestElevation: highestElevation > -Double.greatestFiniteMagnitude ? highestElevation : nil,
            lowestElevation: lowestElevation < Double.greatestFiniteMagnitude ? lowestElevation : nil,
            pointCount: locations.count
        )

        let trackURL = checkpointTrackURL
        let metaURL = checkpointMetaURL

        Task {
            let trackData = TrackEncoder.encodeV5(locations, heartRates: heartRates, powers: powers)

            let metaData = await MainActor.run {
                try? JSONEncoder().encode(meta)
            }

            DispatchQueue.global(qos: .utility).async { [weak self] in
                do {
                    try trackData.write(to: trackURL, options: .atomic)
                } catch {
                    print("[Checkpoint] Failed to write track: \(error)")
                    return
                }

                guard let metaData else { return }

                do {
                    try metaData.write(to: metaURL, options: .atomic)
                } catch {
                    print("[Checkpoint] Failed to write meta: \(error)")
                    return
                }

                DispatchQueue.main.async {
                    self?.lastCheckpointLocationCount = locations.count
                }
            }
        }
    }

    private func deleteCheckpointFiles() {
        try? FileManager.default.removeItem(at: checkpointTrackURL)
        try? FileManager.default.removeItem(at: checkpointMetaURL)
    }

    func recoverCheckpointIfNeeded() {
        guard !isActive else { return }
        let fm = FileManager.default
        guard fm.fileExists(atPath: checkpointMetaURL.path),
              fm.fileExists(atPath: checkpointTrackURL.path) else { return }

        print("[Checkpoint] Found checkpoint, attempting recovery...")

        let metaURL = checkpointMetaURL
        let trackURL = checkpointTrackURL

        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            guard let metaData = try? Data(contentsOf: metaURL),
                  let meta = decodeCheckpointMeta(metaData) else {
                print("[Checkpoint] Could not decode meta, discarding")
                self.deleteCheckpointFiles()
                return
            }

            guard let trackData = try? Data(contentsOf: trackURL), !trackData.isEmpty else {
                print("[Checkpoint] Empty track data, discarding")
                self.deleteCheckpointFiles()
                return
            }

            let trackFilename = "\(meta.rideID.uuidString).track"
            let destURL = ConnectivityManager.ridesDirectory.appendingPathComponent(trackFilename)
            do {
                if FileManager.default.fileExists(atPath: destURL.path) {
                    try FileManager.default.removeItem(at: destURL)
                }
                try FileManager.default.copyItem(at: trackURL, to: destURL)
            } catch {
                print("[Checkpoint] Failed to copy track: \(error)")
                self.deleteCheckpointFiles()
                return
            }

            let summary = RideSummary(
                id: meta.rideID,
                name: meta.name,
                activityType: meta.activityType,
                date: meta.startDate,
                elapsedTime: meta.elapsedTime,
                movingTime: meta.movingTime,
                distance: meta.distance,
                calories: meta.calories,
                elevationGain: meta.elevationGain,
                elevationLoss: meta.elevationLoss,
                avgSpeed: meta.avgSpeed,
                pointCount: meta.pointCount,
                trackFilename: trackFilename,
                maxSpeed: meta.maxSpeed > 0 ? meta.maxSpeed : nil,
                avgPower: meta.avgPower,
                maxPower: meta.maxPower,
                avgHeartRate: meta.avgHeartRate,
                maxHeartRate: meta.maxHeartRate,
                highestElevation: meta.highestElevation,
                lowestElevation: meta.lowestElevation,
                isOnHold: true
            )

            ConnectivityManager.shared.sendRide(summary: summary, trackURL: destURL)
            self.deleteCheckpointFiles()

            DispatchQueue.main.async {
                self.recoveredRideSummary = summary
                print("[Checkpoint] Recovered ride: \(summary.name), \(summary.pointCount) points")
            }
        }
    }

    // MARK: - Hold Ride

    private func currentRideName() -> String {
        if let routeName = initialRouteName { return routeName }
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Morning Ride"
        case 12..<17: return "Afternoon Ride"
        case 17..<21: return "Evening Ride"
        default:      return "Night Ride"
        }
    }

    func holdRide() {
        guard isActive, !isSimulating else { return }

        stopCheckpointTimer()
        stopTelemetryTimer()
        routeInsertionTimer?.invalidate()
        routeInsertionTimer = nil

        if autoPauseState == .tentativeResume {
            commitTentativeBuffer()
        }

        let rideID = currentRideID ?? UUID()
        let trackFilename = "\(rideID.uuidString).track"
        // Write the track directly to the durable rides directory rather than the
        // temporary directory. Combined with an early RideStore save below, this
        // ensures the held ride survives a crash anywhere in the async HK chain.
        let persistentTrackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(trackFilename)

        let locationsToSave = recordedLocations
        let hrsToSave = recordedHeartRates
        let powersToSave = recordedPowers

        // Use the original ride start date so elapsed time spans the whole ride
        let summary = RideSummary(
            id: rideID,
            name: currentRideName(),
            activityType: currentActivity,
            date: initialRideStartDate ?? workoutStartDate ?? Date(),
            elapsedTime: elapsedTime,
            movingTime: movingTime,
            distance: totalDistance,
            calories: activeCalories,
            elevationGain: liveElevationGain,
            elevationLoss: liveElevationLoss,
            avgSpeed: movingTime > 0 ? totalDistance / movingTime : 0,
            pointCount: locationsToSave.count,
            trackFilename: trackFilename,
            maxSpeed: maxSpeed > 0 ? maxSpeed : nil,
            avgPower: powerSampleCount > 0 ? averagePower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
            highestElevation: highestElevation > -Double.greatestFiniteMagnitude ? highestElevation : nil,
            lowestElevation: lowestElevation < Double.greatestFiniteMagnitude ? lowestElevation : nil,
            isOnHold: true
        )

        let trackData = TrackEncoder.encodeV5(locationsToSave, heartRates: hrsToSave, powers: powersToSave)
        do {
            // Atomic write so we never end up with a half-written track file even
            // if the watch power-cycles during the write.
            try trackData.write(to: persistentTrackURL, options: .atomic)
        } catch {
            print("[Hold] Failed to write track: \(error)")
            return
        }

        // Persist the held ride to disk + RideStore SYNCHRONOUSLY before any of the
        // teardown / async HK work. RideStore.update writes the summary JSON to the
        // same `rides/` directory ConnectivityManager uses. If anything below fails
        // or the app crashes, the held ride is already durable on the watch and
        // `retryPendingTransfers` (fired on reachability change) will re-send it to
        // the phone — TransferLedger keeps the entry pending until acked.
        rideStore?.update(summary)
        TransferLedger.shared.recordTransfer(rideID: summary.id)

        // Surface a held-ride summary screen so the user sees feedback after the
        // countdown — without this, holdRide silently tears down and the view
        // jumps back to the route list with no acknowledgment that anything happened.
        // The cleanup() check `if completedRideSummary == nil` keeps `isActive` true
        // while a summary is showing, so ContentView routes to RideSummaryView.
        completedRideSummary = WatchRideSummary(
            distance: totalDistance,
            movingTime: movingTime,
            elapsedTime: elapsedTime,
            avgSpeed: movingTime > 0 ? totalDistance / movingTime : 0,
            maxSpeed: maxSpeed,
            elevationGain: liveElevationGain,
            calories: activeCalories,
            avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : 0,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : 0,
            avgPower: powerSampleCount > 0 ? averagePower : 0,
            maxPower: maxPower > 0 ? maxPower : 0,
            isHeld: true
        )

        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.workoutManager = nil
        VoiceAlertTransport.shared.stop()
        navigation.reset()
        isMirroringReady = false
        mirroringRetryWorkItem?.cancel()
        mirroringRetryWorkItem = nil

        isLocalStateChange = true
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
        stopDisplayTimer()
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        // Checkpoint files are only deleted AFTER the held ride is fully durable on
        // disk AND we've kicked off the transfer to the phone. If we deleted them
        // up-front and then crashed mid-async, both the checkpoint *and* the in-
        // flight summary would be gone.

        // Finish the HK session for this segment so it saves to Fitness
        let endDate = Date()
        session?.end()

        let finalBatch = pendingRouteLocations
        pendingRouteLocations = []
        // Capture this segment's builders so they survive a later `continueHeldRide`
        // reassigning self.builder/self.routeBuilder before our async notify fires.
        let pendingBuilder = builder
        let pendingRouteBuilder = routeBuilder
        if !finalBatch.isEmpty, let pendingRouteBuilder {
            routeInsertGroup.enter()
            pendingRouteBuilder.insertRouteData(finalBatch) { [weak self] _, _ in
                self?.routeInsertGroup.leave()
            }
        }

        // Wait for ALL in-flight inserts (timer flushes + final batch) before
        // finishing the route, otherwise the workout saves with a missing or
        // partial route.
        routeInsertGroup.notify(queue: .main) { [weak self] in
            guard let self else { return }
            pendingBuilder?.endCollection(withEnd: endDate) { _, _ in
                pendingBuilder?.finishWorkout { [weak self] workout, error in
                    guard let self else { return }
                    if let workout {
                        pendingRouteBuilder?.finishRoute(with: workout, metadata: nil) { _, _ in
                            print("[Hold] HK segment saved to Fitness")
                        }
                    } else {
                        print("[Hold] HK segment not saved: \(String(describing: error))")
                    }
                    DispatchQueue.main.async {
                        // The track + summary are already on disk and in RideStore;
                        // sendRide will detect that the destination matches the
                        // source and skip the copy, then notify + transfer to phone.
                        ConnectivityManager.shared.sendRide(summary: summary, trackURL: persistentTrackURL)
                        self.deleteCheckpointFiles()
                        self.cleanup()
                    }
                }
            }
        }
    }

    func continueHeldRide(summary: RideSummary) {
        guard !isActive else { return }

        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(summary.trackFilename)
        guard let trackData = try? Data(contentsOf: trackURL) else {
            print("[Continue] Could not load track for held ride")
            return
        }

        let points = TrackEncoder.decodeV5Full(trackData)
        let hrValues = points.compactMap { $0.heartRate > 0 ? $0.heartRate : nil }
        let pwValues = points.compactMap { $0.power > 0 ? $0.power : nil }

        continuationBase = summary
        initialRideStartDate = summary.date

        // Pre-populate arrays from old track
        recordedLocations = points.map { pt in
            CLLocation(
                coordinate: CLLocationCoordinate2D(latitude: pt.lat, longitude: pt.lon),
                altitude: pt.altitude,
                horizontalAccuracy: 0,
                verticalAccuracy: 0,
                timestamp: Date(timeIntervalSince1970: pt.timestamp))
        }
        recordedHeartRates = points.map { $0.heartRate > 0 ? $0.heartRate : nil }
        recordedPowers = points.map { $0.power > 0 ? $0.power : nil }

        // Restore running sums for accurate averages over the whole ride
        heartRateSum = hrValues.reduce(0, +)
        heartRateSampleCount = hrValues.count
        powerSum = pwValues.reduce(0, +)
        powerSampleCount = pwValues.count

        // Restore accumulated stats
        totalDistance = summary.distance
        movingTime = summary.movingTime
        timerAccumulated = summary.elapsedTime
        liveElevationGain = summary.elevationGain
        liveElevationLoss = summary.elevationLoss
        maxSpeed = summary.maxSpeed ?? 0
        maxHeartRate = summary.maxHeartRate ?? 0
        maxPower = summary.maxPower ?? 0
        highestElevation = summary.highestElevation ?? -Double.greatestFiniteMagnitude
        lowestElevation = summary.lowestElevation ?? Double.greatestFiniteMagnitude
        averageHeartRate = heartRateSampleCount > 0 ? heartRateSum / Double(heartRateSampleCount) : 0
        averagePower = powerSampleCount > 0 ? powerSum / Double(powerSampleCount) : 0

        // Stable ID so the final save overwrites the held summary on phone
        currentRideID = summary.id
        lastCheckpointLocationCount = recordedLocations.count

        start(activity: summary.activityType)
    }

    func finalizeHeldRide(summary: RideSummary) {
        guard !isActive else { return }

        var completed = summary
        completed.isOnHold = nil
        completed.wasAutoFinalized = nil

        // Update local store immediately
        rideStore?.update(completed)

        // Re-send to phone so it receives the updated (completed) summary
        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(summary.trackFilename)
        ConnectivityManager.shared.sendRide(summary: completed, trackURL: trackURL)
    }

    func discardHeldRide(summary: RideSummary) {
        rideStore?.delete(summary)
        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(summary.trackFilename)
        try? FileManager.default.removeItem(at: trackURL)
        // Notify phone to remove it as well
        ConnectivityManager.shared.sendDiscardRide(rideID: summary.id)
        print("[Hold] Discarded held ride: \(summary.name)")
    }

    func autoFinalizeHeldRideIfNeeded() {
        guard let held = rideStore?.heldRide else { return }

        var completed = held
        completed.isOnHold = nil
        completed.wasAutoFinalized = true

        rideStore?.update(completed)
        let trackURL = ConnectivityManager.ridesDirectory.appendingPathComponent(held.trackFilename)
        ConnectivityManager.shared.sendRide(summary: completed, trackURL: trackURL)
        print("[Hold] Auto-finalized held ride before new ride: \(held.name)")
    }

    private func sendTelemetry() {
        guard isMirroringReady, let workoutSession = session else { return }

        let avgSpeed = movingTime > 0 ? totalDistance / movingTime : 0

        var payload: [String: String] = [
            "type": "telemetry",
            "ts": String(Date().timeIntervalSince1970),
            "elapsedTime": String(elapsedTime),
            "movingTime": String(movingTime),
            "distance": String(totalDistance),
            "avgSpeed": String(avgSpeed),
            "speed": String(speed),
            "isPaused": String(isPaused),
            "isAutoPaused": String(isAutoPaused),
        ]

        if heartRate > 0 {
            payload["heartRate"] = String(heartRate)
        }
        if maxSpeed > 0 { payload["maxSpeed"] = String(maxSpeed) }
        if averageHeartRate > 0 { payload["avgHR"] = String(averageHeartRate) }
        if maxHeartRate > 0 { payload["maxHR"] = String(maxHeartRate) }
        if activeCalories > 0 { payload["calories"] = String(activeCalories) }
        if currentElevation != 0 { payload["elevation"] = String(currentElevation) }
        if liveElevationGain > 0 { payload["elevGain"] = String(liveElevationGain) }
        if liveElevationLoss > 0 { payload["elevLoss"] = String(liveElevationLoss) }
        if highestElevation > -Double.greatestFiniteMagnitude { payload["highElev"] = String(highestElevation) }
        if currentGrade != 0 { payload["grade"] = String(currentGrade) }
        if estimatedPower > 0 { payload["power"] = String(estimatedPower) }

        if let loc = currentLocation {
            payload["lat"] = String(loc.coordinate.latitude)
            payload["lon"] = String(loc.coordinate.longitude)
        }

        // Navigation data (when a route is loaded)
        if hasRoute {
            payload["distToTurn"] = String(navigation.distanceToNextTurn)
            payload["routeRemaining"] = String(navigation.distanceRemaining)
            payload["isOffRoute"] = String(navigation.isOffRoute)
            if let routeID = activeRoute?.id {
                payload["activeRouteID"] = routeID.uuidString
            }
            if navigation.isOffRoute {
                payload["distOffRoute"] = String(navigation.nearestRouteDistance)
            }

            if let turn = navigation.nextTurn {
                payload["turnDir"] = turn.direction.label
                payload["turnIcon"] = turn.direction.icon
                if let desc = turn.description {
                    payload["turnCue"] = desc
                }
            }

        }

        guard let data = try? JSONEncoder().encode(payload) else { return }

        workoutSession.sendToRemoteWorkoutSession(data: data) { [weak self] success, error in
            if let error = error {
                print("[Telemetry] send error: \(error)")
                self?.markMirroringFailed()
            }
        }
    }

    private func markMirroringFailed() {
        DispatchQueue.main.async {
            guard self.isActive else { return }
            self.isMirroringReady = false
            self.scheduleMirroringRetry()
        }
    }

    private func scheduleMirroringRetry() {
        // Workout mirroring should keep the phone alive end-to-end. If a
        // single send fails, give the link a short cool-down then optimistic-
        // ally re-enable — the next send will tell us if it's actually back.
        mirroringRetryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isActive, self.session != nil else { return }
            self.isMirroringReady = true
            self.mirroringRetryWorkItem = nil
        }
        mirroringRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 3, execute: item)
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 50 else { return }
        // GPS course is more accurate than compass for direction of travel while cycling.
        // Use it whenever the signal is valid and the rider is moving.
        if location.course >= 0 && location.speed > 0.5 {
            DispatchQueue.main.async { self.heading = location.course }
        }
        processLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            // Fall back to compass only when stopped (GPS course is unavailable/unreliable at low speed)
            if self.speed <= 0.5 {
                self.heading = newHeading.trueHeading
            }
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("Location error: \(error)")
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways:
            print("Location authorized")
        case .denied, .restricted:
            print("Location denied")
        default:
            break
        }
    }
}

extension WorkoutManager: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        print("Workout state: \(fromState.rawValue) → \(toState.rawValue)")

        if isLocalStateChange {
            // Local action (pause/resume/stop called on this device) —
            // internal state is already synced, just reset the guard.
            isLocalStateChange = false
            return
        }

        // Remote state change (initiated from phone via mirrored session).
        // Sync internal WorkoutManager state to match.
        DispatchQueue.main.async { [weak self] in
            guard let self = self, self.isActive else { return }

            switch toState {
            case .paused where fromState == .running:
                print("[Remote] Pause received from phone")
                // Sync timers and isPaused flag without re-calling session?.pause()
                if let start = self.timerStart {
                    self.timerAccumulated += Date().timeIntervalSince(start)
                }
                self.timerStart = nil
                self.isPaused = true
                self.locationManager.stopUpdatingLocation()
                self.locationManager.stopUpdatingHeading()
                if self.autoPauseState == .tentativeResume {
                    self.clearTentativeBuffer()
                }
                self.autoPauseState = .moving

            case .running where fromState == .paused:
                print("[Remote] Resume received from phone")
                self.timerStart = Date()
                self.startDisplayTimer()
                self.isPaused = false
                self.skipNextDistanceGap = true
                self.slowSampleCount = 0
                self.autoPauseState = .moving
                self.resumeGraceUntil = Date().addingTimeInterval(5)
                self.locationManager.startUpdatingLocation()
                self.locationManager.startUpdatingHeading()

            case .ended, .stopped:
                print("[Remote] End received from phone")
                self.stop(save: true)

            default:
                break
            }
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("Workout session error: \(error)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didDisconnectFromRemoteDeviceWithError error: Error?) {
        print("[Mirroring] Disconnected from phone: \(error?.localizedDescription ?? "clean")")
        markMirroringFailed()
    }

    /// Receive messages from the phone (ack channel for mirrored speech, etc.).
    /// Currently the only message type is "speechDone" — fired when the phone
    /// finishes playing a mirrored utterance so the watch can advance its
    /// alert queue based on real completion instead of a duration estimate.
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let now = Date().timeIntervalSince1970

        for item in data {
            guard let payload = try? JSONDecoder().decode([String: String].self, from: item),
                  let type = payload["type"] else {
                continue
            }

            // Drop very old messages (e.g. relaunch flush).
            if let tsString = payload["ts"], let ts = Double(tsString) {
                if now - ts > 10 { continue }
            }

            // Speech itself flows watch→phone via WCSession (plan §1).
            // But the phone→watch ACK comes back through the HK mirror
            // channel: real-world telemetry showed WCSession sendMessage
            // hitting WCErrorCodeDeliveryFailed on phone→watch even
            // mid-mirrored-workout. The HK mirror channel is reliable
            // bidirectionally for the duration of the workout, so we use
            // it for the small ack hop and let VoiceAlertTransport
            // dispatch via the same hook either path would have used.
            switch type {
            case "alertAck":
                guard let idStr = payload["id"], let id = UUID(uuidString: idStr) else { continue }
                DispatchQueue.main.async {
                    ConnectivityManager.shared.onAlertAckReceived?(id)
                }
            default:
                break
            }
        }
    }
}

extension WorkoutManager: HKLiveWorkoutBuilderDelegate {
    func workoutBuilder(_ workoutBuilder: HKLiveWorkoutBuilder,
                        didCollectDataOf collectedTypes: Set<HKSampleType>) {
        for type in collectedTypes {
            guard let quantityType = type as? HKQuantityType else { continue }
            let statistics = workoutBuilder.statistics(for: quantityType)

            DispatchQueue.main.async {
                switch quantityType {
                case HKQuantityType(.heartRate):
                    let unit = HKUnit.count().unitDivided(by: .minute())
                    let hr = statistics?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
                    self.heartRate = hr
                    if hr > 0 {
                        self.heartRateSum += hr
                        self.heartRateSampleCount += 1
                        self.averageHeartRate = self.heartRateSum / Double(self.heartRateSampleCount)
                        if hr > self.maxHeartRate { self.maxHeartRate = hr }
                        // Per-split HR accumulation
                        self.splitHRSum += hr
                        self.splitHRCount += 1
                        if hr > self.splitMaxHR { self.splitMaxHR = hr }
                    }
                case HKQuantityType(.activeEnergyBurned):
                    let unit = HKUnit.kilocalorie()
                    self.activeCalories = statistics?.sumQuantity()?.doubleValue(for: unit) ?? 0
                default:
                    break
                }
            }
        }
    }

    func workoutBuilderDidCollectEvent(_ workoutBuilder: HKLiveWorkoutBuilder) {}
}
