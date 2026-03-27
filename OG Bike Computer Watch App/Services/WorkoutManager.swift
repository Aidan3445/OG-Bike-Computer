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

enum AutoPauseState {
    case moving
    case paused
    case tentativeResume
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
    private let gradeWindowDistance: Double = 50 // meters of horizontal travel for grade calc
    private var heartRateSum: Double = 0
    private var heartRateSampleCount: Int = 0
    private var powerSum: Double = 0
    private var powerSampleCount: Int = 0
    private var liveElevRefAltitude: Double?
    private let liveElevMinDelta: Double = 2.0

    // User-configurable mass for power estimate (synced from phone)
    var riderMass: Double = 75  // kg
    var bikeMass: Double = 10   // kg
    var totalMass: Double { riderMass + bikeMass }

    var onRideCompleted: ((RideSummary) -> Void)?

    private var routeInsertionTimer: Timer?
    private var pendingRouteLocations: [CLLocation] = []
    @Published var recordedLocations: [CLLocation] = []

    private let healthStore = HKHealthStore()
    private(set) var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?

    private let locationManager = CLLocationManager()

    private var timerStart: Date?
    private var timerAccumulated: TimeInterval = 0
    private var displayTimer: Timer?
    private var workoutStartDate: Date?

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

    // Mirroring: set true after delay post-mirroring, false on error/disconnect.
    // Re-arms via DispatchWorkItem after 10s to detect phone reconnection.
    private var isMirroringReady = false
    private var mirroringRetryWorkItem: DispatchWorkItem?

    // SIM
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
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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

        workoutStartDate = Date()
        timerStart = workoutStartDate
        timerAccumulated = 0
        startDisplayTimer()

        isActive = true
        isPaused = false
        autoPauseState = .moving
        slowSampleCount = 0
        lastCommittedLocation = nil
        skipNextDistanceGap = false
    }

    func processLocation(_ location: CLLocation) {
        DispatchQueue.main.async {
            self.currentLocation = location
            self.speed = max(location.speed, 0)

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
                    isActivelyMoving: self.autoPauseState == .moving)
            }

            guard !self.isSimulating else { return }

            // Battery optimization only with a route (needs turn distances)
            if self.hasRoute {
                let mode = self.battery.recommendedMode(
                    distanceToNextTurn: self.navigation.distanceToNextTurn,
                    isOffRoute: self.navigation.isOffRoute,
                    speed: self.speed)
                self.battery.apply(mode: mode, to: self.locationManager)
            }

            self.updateAutoPause()

            // Recording + distance based on auto-pause state
            switch self.autoPauseState {
            case .moving:
                self.accumulateDistance(location)
                self.recordedLocations.append(location)
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

            // Battery management
            let mode = self.battery.recommendedMode(
                distanceToNextTurn: self.navigation.distanceToNextTurn,
                isOffRoute: self.navigation.isOffRoute,
                speed: self.speed)
            self.battery.apply(mode: mode, to: self.locationManager)

            self.updateAutoPause()
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
    }

    private func flushRouteLocations() {
        guard !pendingRouteLocations.isEmpty else { return }
        let batch = pendingRouteLocations
        pendingRouteLocations = []

        routeBuilder?.insertRouteData(batch) { success, error in
            if let error = error {
                print("Route insert error: \(error)")
            }
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

    private func commitTentativeBuffer() {
        // Add only the internal distance of the buffer (no gap bridging)
        totalDistance += tentativeDistance

        // Move staged locations into the real recording
        recordedLocations.append(contentsOf: tentativeLocations)
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

    func start(activity: ActivityType) {
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

        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        startRouteInsertion()

        // reset() THEN configureAudioSession() — order matters!
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.configureAudioSession()
        VoiceNavigator.shared.workoutManager = self

        isMirroringReady = false
        session?.startMirroringToCompanionDevice { [weak self] success, error in
            print("[Mirroring] Start mirroring result: success=\(success), error=\(String(describing: error))")
            if success {
                DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
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

        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()

        workoutStartDate = Date()
        timerStart = workoutStartDate
        timerAccumulated = 0
        startDisplayTimer()

        isActive = true
        isPaused = false
        autoPauseState = .moving
        slowSampleCount = 0
        lastCommittedLocation = nil
        skipNextDistanceGap = false
    }

    func pauseSession() {
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
        let speedMPH = speed * 2.23694
        let pauseThreshold = 1.0
        let resumeThreshold = 2.0

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
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
        stopDisplayTimer()
        routeInsertionTimer?.invalidate()
        routeInsertionTimer = nil
        
        if autoPauseState == .tentativeResume {
            commitTentativeBuffer()
        }

        // Kill voice and navigation IMMEDIATELY
        VoiceNavigator.shared.reset()
        VoiceNavigator.shared.workoutManager = nil
        navigation.reset()

        isMirroringReady = false
        mirroringRetryWorkItem?.cancel()
        mirroringRetryWorkItem = nil

        if !isSimulating {
            locationManager.stopUpdatingLocation()
            locationManager.stopUpdatingHeading()
            session?.end()
        }

        if save && !isSimulating {
            let finalBatch = pendingRouteLocations
            pendingRouteLocations = []
            let endDate = Date()

            print("[stop] saving ride, \(recordedLocations.count) recorded locations")

            let insertGroup = DispatchGroup()
            if !finalBatch.isEmpty {
                insertGroup.enter()
                routeBuilder?.insertRouteData(finalBatch) { _, error in
                    if let error = error {
                        print("[stop] final route insert error: \(error)")
                    }
                    insertGroup.leave()
                }
            }

            insertGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }
                print("[stop] endCollection")

                self.builder?.endCollection(withEnd: endDate) { success, error in
                    if let error = error {
                        print("[stop] end collection error: \(error)")
                    }

                    self.builder?.finishWorkout { [weak self] workout, error in
                        guard let self = self, let workout = workout else {
                            print("[stop] finish workout error: \(String(describing: error))")
                            self?.exportAndTransferRide()
                            self?.cleanup()
                            return
                        }

                        print("[stop] workout saved, attaching route...")

                        self.routeBuilder?.finishRoute(with: workout, metadata: nil) { route, error in
                            if let error = error {
                                print("[stop] finish route error: \(error)")
                            } else {
                                print("[stop] route attached successfully")
                            }
                            self.exportAndTransferRide()
                            self.cleanup()
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
            cleanup()
        }
    }

    private func cleanup() {
        DispatchQueue.main.async {
            self.isActive = false
            self.isPaused = false
            self.isSimulating = false
            self.isMirroringReady = false
            self.recordedLocations = []
            self.pendingRouteLocations = []
            self.autoPauseState = .moving
            self.slowSampleCount = 0
            self.lastCommittedLocation = nil
            self.skipNextDistanceGap = false
            self.clearTentativeBuffer()
            self.speed = 0
            self.totalDistance = 0
            self.workoutStartDate = nil
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
                // Elapsed time always counts from workout start (wall-clock time)
                if let startDate = self.workoutStartDate {
                    self.elapsedTime = Date().timeIntervalSince(startDate)
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
            let alpha = 0.3
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
                    let alpha = 0.4
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
        navigation.reset()
        needsAnchor = false
        VoiceNavigator.shared.resetForRouteSwap()
    }

    private func handleTurnAlert(_ alert: NavigationTracker.TurnAlert) {
        switch alert {
        case .warning(_):
            WKInterfaceDevice.current().play(.click)
        case .imminent(let turn):
            switch turn.direction {
            case .left, .slightLeft, .sharpLeft:
                WKInterfaceDevice.current().play(.directionDown)
            case .right, .slightRight, .sharpRight:
                WKInterfaceDevice.current().play(.directionUp)
            case .uTurn:
                WKInterfaceDevice.current().play(.failure)
            case .straight:
                WKInterfaceDevice.current().play(.success)
            }
        }
    }

    private func exportAndTransferRide() {
        let hour = Calendar.current.component(.hour, from: Date())
        let timeOfDay: String
        switch hour {
        case 5..<12: timeOfDay = "Morning Ride"
        case 12..<17: timeOfDay = "Afternoon Ride"
        case 17..<21: timeOfDay = "Evening Ride"
        default: timeOfDay = "Night Ride"
        }
        
        let rideName: String
        if let routeName = navigation.processedRoute?.name {
            rideName = "\(routeName) - \(timeOfDay)"
        } else {
            rideName = timeOfDay
        }   

        let activity = currentActivity

        let avgSpeed = elapsedTime > 0 ? totalDistance / elapsedTime : 0
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

        let trackData = TrackEncoder.encode(recordedLocations)
        let trackFilename = "\(UUID().uuidString).track"
        let tempURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(trackFilename)

        do {
            try trackData.write(to: tempURL)
        } catch {
            print("Failed to write track data: \(error)")
            return
        }

        let summary = RideSummary(
            id: UUID(),
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
            pointCount: recordedLocations.count,
            trackFilename: trackFilename,
            maxSpeed: maxSpeed > 0 ? maxSpeed : nil,
            avgPower: powerSampleCount > 0 ? averagePower : nil,
            maxPower: maxPower > 0 ? maxPower : nil,
            avgHeartRate: heartRateSampleCount > 0 ? averageHeartRate : nil,
            maxHeartRate: maxHeartRate > 0 ? maxHeartRate : nil,
            highestElevation: highestElevation > -Double.greatestFiniteMagnitude ? highestElevation : nil,
            lowestElevation: lowestElevation < Double.greatestFiniteMagnitude ? lowestElevation : nil)

        DispatchQueue.main.async {
            self.onRideCompleted?(summary)
            ConnectivityManager.shared.sendRide(summary: summary, trackURL: tempURL)
        }
    }

    // Speech routing to phone

    func sendSpeechToPhone(_ text: String, completion: @escaping (Bool) -> Void) {
        guard let workoutSession = self.session else {
            completion(false)
            return
        }

        guard isMirroringReady else {
            completion(false)
            return
        }

        let payload: [String: String] = [
            "type": "speech",
            "text": text,
            "ts": String(Date().timeIntervalSince1970)
        ]
        guard let data = try? JSONEncoder().encode(payload) else {
            completion(false)
            return
        }

        workoutSession.sendToRemoteWorkoutSession(data: data) { [weak self] success, error in
            if let error = error {
                print("[Speech] send error: \(error)")
                self?.markMirroringFailed()
                completion(false)
            } else {
                completion(success)
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
        mirroringRetryWorkItem?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.isActive, self.session != nil else { return }
            self.isMirroringReady = true
            self.mirroringRetryWorkItem = nil
        }
        mirroringRetryWorkItem = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 10, execute: item)
    }
}

extension WorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 50 else { return }
        processLocation(location)
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        guard newHeading.headingAccuracy >= 0 else { return }
        DispatchQueue.main.async {
            self.heading = newHeading.trueHeading
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
