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

#if os(watchOS)
import WatchKit
#endif

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
    private var session: HKWorkoutSession?
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
    private let autoPauseWindow = 5
    @Published var movingTime: TimeInterval = 0
    private var isWristDown = false

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

        autoPauseSpeedSamples.append(speedMPH)
        if autoPauseSpeedSamples.count > autoPauseWindow {
            autoPauseSpeedSamples.removeFirst()
        }

        let allSlow = autoPauseSpeedSamples.count >= autoPauseWindow &&
                      autoPauseSpeedSamples.allSatisfy { $0 < 1.0 }
        let moving = speedMPH >= 2.0

        if allSlow && !isAutoPaused && !isPaused {
            pauseSession()
            isAutoPaused = true
        } else if moving && isAutoPaused {
            resumeSession()
            isAutoPaused = false
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
        locationManager.stopUpdatingLocation()
        locationManager.stopUpdatingHeading()

        session?.end()

        if save {
            let finalBatch = pendingRouteLocations
            pendingRouteLocations = []

            let endDate = Date()

            let insertGroup = DispatchGroup()
            if !finalBatch.isEmpty {
                insertGroup.enter()
                routeBuilder?.insertRouteData(finalBatch) { _, error in
                    if let error = error {
                        print("Final route insert error: \(error)")
                    }
                    insertGroup.leave()
                }
            }

            insertGroup.notify(queue: .main) { [weak self] in
                guard let self = self else { return }

                self.builder?.endCollection(withEnd: endDate) { success, error in
                    if let error = error {
                        print("End collection error: \(error)")
                    }

                    self.builder?.finishWorkout { [weak self] workout, error in
                        guard let self = self, let workout = workout else {
                            print("Finish workout error: \(String(describing: error))")
                            return
                        }

                        print("Workout saved: \(workout)")

                        self.routeBuilder?.finishRoute(with: workout, metadata: nil) { route, error in
                            if let error = error {
                                print("Finish route error: \(error)")
                            } else {
                                print("Route attached to workout successfully")
                                self.exportAndTransferRide()
                            }
                        }
                    }
                }
            }
        } else {
            builder?.discardWorkout()
        }

        DispatchQueue.main.async {
            self.isActive = false
            self.isPaused = false
            self.recordedLocations = []
            self.pendingRouteLocations = []
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
       
    #if os(watchOS)
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
        for i in 1..<recordedLocations.count {
            let delta = recordedLocations[i].altitude - recordedLocations[i - 1].altitude
            if delta > 0 { elevGain += delta }
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
            avgSpeed: avgSpeed,
            pointCount: recordedLocations.count,
            trackFilename: trackFilename)

        DispatchQueue.main.async {
            self.onRideCompleted?(summary)
        }

        ConnectivityManager.shared.sendRide(summary: summary, trackURL: tempURL)
    }
    #endif
}

extension WorkoutManager: CLLocationManagerDelegate {
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        guard location.horizontalAccuracy >= 0,
              location.horizontalAccuracy < 50 else { return }

        DispatchQueue.main.async {
            if let previous = self.currentLocation {
                self.totalDistance += location.distance(from: previous)
            }
            self.currentLocation = location
            self.speed = max(location.speed, 0)
            self.recordedLocations.append(location)
            self.pendingRouteLocations.append(location)

            // Navigation
            if let alert = self.navigation.update(location: location) {
                self.handleTurnAlert(alert)
            }

            // Battery management — adjust GPS frequency
            let mode = self.battery.recommendedMode(
                distanceToNextTurn: self.navigation.distanceToNextTurn,
                isOffRoute: self.navigation.isOffRoute,
                speed: self.speed)
            self.battery.apply(mode: mode, to: self.locationManager)

            // Auto-pause logic
            self.updateAutoPause()
        }
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
