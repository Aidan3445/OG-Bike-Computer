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

    let navigation = NavigationTracker()

    private let battery = BatteryManager()
    @Published var isAutoPaused = false
    private var autoPauseSpeedSamples: [Double] = []
    private let pauseWindow = 5
    private let resumeWindow = 3
    private var resumeCandidateCount = 0
    private var tentativeLocations: [CLLocation] = []
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

        timerStart = Date()
        timerAccumulated = 0
        startDisplayTimer()

        isActive = true
        isPaused = false
        isAutoPaused = false
    }

    func processLocation(_ location: CLLocation) {
        DispatchQueue.main.async {
            if let previous = self.currentLocation {
                self.totalDistance += location.distance(from: previous)
            }
            self.currentLocation = location
            self.speed = max(location.speed, 0)

            if !self.isSimulating {
                self.recordedLocations.append(location)
                self.pendingRouteLocations.append(location)
            }

            if let alert = self.navigation.update(location: location) {
                self.handleTurnAlert(alert)
            }

            VoiceNavigator.shared.update(nav: self.navigation, speed: self.speed)

            if !self.isSimulating {
                let mode = self.battery.recommendedMode(
                    distanceToNextTurn: self.navigation.distanceToNextTurn,
                    isOffRoute: self.navigation.isOffRoute,
                    speed: self.speed)
                self.battery.apply(mode: mode, to: self.locationManager)

                self.updateAutoPause()
            }
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

        timerStart = Date()
        timerAccumulated = 0
        startDisplayTimer()

        isActive = true
        isPaused = false
        isAutoPaused = false
    }

    func pauseSession() {
        session?.pause()
        if let start = timerStart {
            timerAccumulated += Date().timeIntervalSince(start)
        }
        timerStart = nil
        stopDisplayTimer()
        isPaused = true
    }

    func pause() {
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()
        pauseSession()
    }

    func resumeSession() {
        session?.resume()
        timerStart = Date()
        startDisplayTimer()
        isPaused = false
        if isAutoPaused {
            autoPauseSpeedSamples.removeAll()
        }
    }

    func resume() {
        locationManager.startUpdatingLocation()
        locationManager.startUpdatingHeading()
        resumeSession()
    }

    private func updateAutoPause() {
        let speedMPH = speed * 2.23694
        let pauseThreshold = 1.0
        let resumeThreshold = 2.0

        if !isAutoPaused {
            autoPauseSpeedSamples.append(speedMPH)
            if autoPauseSpeedSamples.count > pauseWindow {
                autoPauseSpeedSamples.removeFirst()
            }

            let allSlow = autoPauseSpeedSamples.count >= pauseWindow &&
                autoPauseSpeedSamples.allSatisfy { $0 < pauseThreshold }

            if allSlow && !isPaused {
                pauseSession()
                isAutoPaused = true
                resumeCandidateCount = 0
                tentativeLocations.removeAll()
            }
        } else {
            if speedMPH >= resumeThreshold {
                resumeCandidateCount += 1
                if let loc = currentLocation {
                    tentativeLocations.append(loc)
                    pendingRouteLocations.append(loc)
                }
                if resumeCandidateCount >= resumeWindow {
                    recordedLocations.append(contentsOf: tentativeLocations)
                    tentativeLocations.removeAll()
                    autoPauseSpeedSamples.removeAll()
                    resumeSession()
                    isAutoPaused = false
                }
            } else {
                if !tentativeLocations.isEmpty {
                    let discardCount = tentativeLocations.count
                    if pendingRouteLocations.count >= discardCount {
                        pendingRouteLocations.removeLast(discardCount)
                    }
                    tentativeLocations.removeAll()
                }
                resumeCandidateCount = 0
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
            self.isAutoPaused = false
            self.isMirroringReady = false
            self.recordedLocations = []
            self.pendingRouteLocations = []
            self.tentativeLocations = []
            self.resumeCandidateCount = 0
            self.autoPauseSpeedSamples = []
            self.speed = 0
            self.totalDistance = 0
            self.elapsedTime = 0
            self.movingTime = 0
            self.heartRate = 0
            self.activeCalories = 0
            self.currentLocation = nil
        }
    }

    func discard() {
        stop(save: false)
    }

    private func startDisplayTimer() {
        displayTimer?.invalidate()
        displayTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            guard let self = self, let start = self.timerStart else { return }
            DispatchQueue.main.async {
                self.elapsedTime = self.timerAccumulated + Date().timeIntervalSince(start)
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

    func loadRoute(_ route: Route) {
        let processed = RouteProcessor.process(route)
        navigation.load(processed)
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
        let rideName = navigation.processedRoute?.name ?? "Ride"
        let activity = currentActivity

        let avgSpeed = elapsedTime > 0 ? totalDistance / elapsedTime : 0
        var elevGain: Double = 0
        var elevLoss: Double = 0
        if recordedLocations.count > 0 {
            for i in 1..<recordedLocations.count {
                let delta = recordedLocations[i].altitude - recordedLocations[i - 1].altitude
                if delta > 0 { elevGain += delta }
                else { elevLoss -= delta }
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
            trackFilename: trackFilename)

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
                    self.heartRate = statistics?.mostRecentQuantity()?.doubleValue(for: unit) ?? 0
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
