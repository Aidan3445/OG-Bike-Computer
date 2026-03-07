//
//  OG_Bike_ComputerApp.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/27/26.
//

import SwiftUI
import CoreLocation
import MapKit
import HealthKit

class AppDelegate: NSObject, UIApplicationDelegate {
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ConnectivityManager.shared.activate()
        locationManager.requestWhenInUseAuthorization()

        // Warm up MapKit
        let warmup = MKMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = warmup.region

        // Request HealthKit auth — required for mirroring to work
        let typesToShare: Set<HKSampleType> = [HKQuantityType.workoutType()]
        let typesToRead: Set<HKObjectType> = [
            HKQuantityType(.heartRate),
            HKQuantityType(.activeEnergyBurned)
        ]
        healthStore.requestAuthorization(toShare: typesToShare, read: typesToRead) { success, error in
            if let error = error {
                print("[HealthKit] iOS auth error: \(error)")
            } else {
                print("[HealthKit] iOS auth: \(success)")
            }
        }

        // Set up workout mirroring handler — keeps the app alive in background
        // when the watch starts a workout, so speech data can be received
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            print("[Mirroring] Received mirrored workout session")
            self?.mirroredSession = mirroredSession
            mirroredSession.delegate = self
        }

        return true
    }
}

extension AppDelegate: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        print("[Mirroring] Session state: \(fromState.rawValue) → \(toState.rawValue)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        print("[Mirroring] Session error: \(error)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        for item in data {
            guard let payload = try? JSONDecoder().decode([String: String].self, from: item),
                  payload["type"] == "speech",
                  let text = payload["text"] else { continue }

            print("[Mirroring] Speaking: \(text)")
            DispatchQueue.main.async {
                PhoneSpeechPlayer.shared.speak(text)
            }
        }
    }
}

@main
struct OG_Bike_ComputerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var routeStore = RouteStore()
    @StateObject private var rideStore = RideStore()

    @State private var importedFileURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(routeStore: routeStore, rideStore: rideStore)
                .onAppear {
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                }
                .onOpenURL { url in
                    handleIncomingFile(url)
                }
        }
    }

    private func handleIncomingFile(_ url: URL) {
        guard url.startAccessingSecurityScopedResource() else {
            importFile(at: url)
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }
        importFile(at: url)
    }

    private func importFile(at url: URL) {
        guard let data = try? Data(contentsOf: url) else {
            print("Could not read shared file: \(url)")
            return
        }
        let parser = GPXParser()
        let parsed = parser.parse(data: data)
        for route in parsed {
            routeStore.save(route)
        }
        if !parsed.isEmpty {
            print("Imported \(parsed.count) route(s) from share sheet")
        }
    }
}
