//
//  HealthKitRecorder.swift
//  OG Bike Computer Watch App
//

import CoreLocation
import HealthKit

/// The ride's HealthKit workout: the session, the live builder that
/// collects heart rate and calories, and the route sent to Fitness.
final class HealthKitRecorder {
    let healthStore = HKHealthStore()
    private(set) var session: HKWorkoutSession?
    private var builder: HKLiveWorkoutBuilder?
    private var routeBuilder: HKWorkoutRouteBuilder?
    private var pendingRoute: [CLLocation] = []
    private var routeFlushTimer: Timer?
    /// Every route insert in flight, so the route only attaches once they've all landed.
    private let routeInserts = DispatchGroup()

    func requestAuthorization() {
        let typesToShare: Set<HKSampleType> = [
            HKQuantityType.workoutType(),
            HKSeriesType.workoutRoute(),
        ]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned),
            HKQuantityType(.distanceCycling),
        ]
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { _, error in
            if let error {
                print("HealthKit auth error: \(error)")
            }
        }
    }

    /// Creates the session, plus a live builder unless it's a sim. Throws if
    /// HealthKit won't make a session.
    func makeSession(
        activity: ActivityType, withBuilder: Bool,
        delegate: HKWorkoutSessionDelegate & HKLiveWorkoutBuilderDelegate
    ) throws {
        let config = HKWorkoutConfiguration()
        config.activityType = activity.hkType
        config.locationType = .outdoor

        session = try HKWorkoutSession(healthStore: healthStore, configuration: config)
        session?.delegate = delegate
        guard withBuilder else { return }
        builder = session?.associatedWorkoutBuilder()
        builder?.dataSource = HKLiveWorkoutDataSource(
            healthStore: healthStore, workoutConfiguration: config)
        builder?.delegate = delegate
    }

    func startActivity() {
        session?.startActivity(with: Date())
    }

    func beginCollection() {
        builder?.beginCollection(withStart: Date()) { _, error in
            if let error {
                print("Failed to begin collection: \(error)")
            }
        }
    }

    func pause() { session?.pause() }
    func resume() { session?.resume() }
    func end() { session?.end() }

    // MARK: - Route

    /// A fresh route for this segment, flushed to HealthKit every 30 s.
    func startRoute() {
        routeBuilder = HKWorkoutRouteBuilder(healthStore: healthStore, device: nil)
        routeFlushTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) {
            [weak self] _ in
            self?.flushRoute()
        }
    }

    func stopRouteTimer() {
        routeFlushTimer?.invalidate()
        routeFlushTimer = nil
    }

    func addRoutePoint(_ location: CLLocation) {
        pendingRoute.append(location)
    }

    func clearPendingRoute() {
        pendingRoute = []
    }

    private func flushRoute() {
        guard !pendingRoute.isEmpty else { return }
        guard let routeBuilder else {
            pendingRoute = []
            return
        }
        let batch = pendingRoute
        pendingRoute = []
        insert(batch, into: routeBuilder)
    }

    private func insert(_ batch: [CLLocation], into routeBuilder: HKWorkoutRouteBuilder) {
        routeInserts.enter()
        routeBuilder.insertRouteData(batch) { [weak self] _, error in
            if let error {
                print("Route insert error: \(error)")
            }
            self?.routeInserts.leave()
        }
    }

    // MARK: - Finishing

    /// Sends the last route points, waits for every route insert, then ends
    /// collection. The segment keeps this ride's builders, so a new ride
    /// started before the callbacks land can't swap them out.
    func endSegment(at endDate: Date, completion: @escaping (HealthKitSegment) -> Void) {
        let segment = HealthKitSegment(builder: builder, routeBuilder: routeBuilder)
        let finalBatch = pendingRoute
        pendingRoute = []
        if !finalBatch.isEmpty, let routeBuilder {
            insert(finalBatch, into: routeBuilder)
        }
        routeInserts.notify(queue: .main) {
            segment.builder?.endCollection(withEnd: endDate) { _, error in
                if let error {
                    print("[HealthKit] end collection error: \(error)")
                }
                completion(segment)
            }
        }
    }

    /// Drops the current workout without saving it.
    func discardWorkout() {
        builder?.discardWorkout()
    }
}

/// One finished stretch of a ride in HealthKit, ready to save or discard.
struct HealthKitSegment {
    let builder: HKLiveWorkoutBuilder?
    let routeBuilder: HKWorkoutRouteBuilder?

    /// Saves the workout, then attaches the route. `completion` gets whether
    /// the workout saved. It runs once the route is attached when
    /// `waitForRoute`, otherwise as soon as the workout saves.
    func save(waitForRoute: Bool, completion: @escaping (_ saved: Bool) -> Void) {
        builder?.finishWorkout { workout, error in
            guard let workout else {
                print("[HealthKit] finish workout error: \(String(describing: error))")
                completion(false)
                return
            }
            routeBuilder?.finishRoute(with: workout, metadata: nil) { _, error in
                if let error {
                    print("[HealthKit] finish route error: \(error)")
                }
                if waitForRoute { completion(true) }
            }
            if !waitForRoute { completion(true) }
        }
    }

    func discard() {
        builder?.discardWorkout()
    }
}
