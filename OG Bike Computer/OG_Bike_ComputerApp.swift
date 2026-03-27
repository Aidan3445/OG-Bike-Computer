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
import os
import AVFAudio

private let mirrorLogger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "Mirroring")

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

        let warmup = MKMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = warmup.region

        // Configure audio session category ONCE at launch.
        // This registers us as a ducking session before any workout starts.
        // If we wait until the first speech arrives, the category change itself
        // causes a full interruption to the music app instead of a duck.
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .interruptSpokenAudioAndMixWithOthers])
        } catch {
            print("[Audio] session config error: \(error)")
        }

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

        // Called on initial mirroring AND on every reconnection (e.g. after
        // this app was killed and HealthKit relaunched it). Each call delivers
        // a NEW valid HKWorkoutSession — the old one is dead.
        // Runs on an anonymous background queue.
        healthStore.workoutSessionMirroringStartHandler = { [weak self] mirroredSession in
            mirrorLogger.notice("[Mirroring] Received mirrored session, state: \(mirroredSession.state.rawValue)")
            // Set new session FIRST — makes the === check in delegates work
            self?.mirroredSession = mirroredSession
            mirroredSession.delegate = self
            // AVSpeechSynthesizer is not thread-safe — reset on main
            DispatchQueue.main.async {
                PhoneSpeechPlayer.shared.resetSession()
            }
        }

        return true
    }
}

extension AppDelegate: HKWorkoutSessionDelegate {
    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didChangeTo toState: HKWorkoutSessionState,
                        from fromState: HKWorkoutSessionState,
                        date: Date) {
        mirrorLogger.info("[Mirroring] Session state: \(fromState.rawValue) → \(toState.rawValue)")

        // THE KEY FIX: Only clean up for the CURRENT session.
        // When ride 1 ends and ride 2 starts quickly:
        //   1. workoutSessionMirroringStartHandler sets mirroredSession = session B
        //   2. Session A's .ended callback arrives late
        //   3. Without this guard, it would call stopImmediately() and kill
        //      session B's fresh synthesizer
        guard workoutSession === mirroredSession else {
            mirrorLogger.info("[Mirroring] Ignoring state change from old session")
            return
        }

        if toState == .ended || toState == .stopped {
            DispatchQueue.main.async {
                PhoneSpeechPlayer.shared.stopImmediately()
            }
            mirroredSession = nil
        }
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didFailWithError error: Error) {
        mirrorLogger.error("[Mirroring] Session error: \(error)")
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didDisconnectFromRemoteDeviceWithError error: Error?) {
        mirrorLogger.notice("[Mirroring] Disconnected: \(error?.localizedDescription ?? "clean")")
        // Don't let old session's disconnect kill new session
        guard workoutSession === mirroredSession else {
            mirrorLogger.info("[Mirroring] Ignoring disconnect from old session")
            return
        }
        DispatchQueue.main.async {
            PhoneSpeechPlayer.shared.stopImmediately()
        }
        mirroredSession = nil
    }

    func workoutSession(_ workoutSession: HKWorkoutSession,
                        didReceiveDataFromRemoteWorkoutSession data: [Data]) {
        let now = Date().timeIntervalSince1970

        for item in data {
            guard let payload = try? JSONDecoder().decode([String: String].self, from: item),
                  payload["type"] == "speech",
                  let text = payload["text"] else {
                continue
            }

            // Discard stale messages — when this app is killed and relaunched,
            // HealthKit delivers all queued data at once
            if let tsString = payload["ts"], let ts = Double(tsString) {
                let age = now - ts
                if age > 10 {
                    mirrorLogger.info("[Mirroring] Discarding stale speech (\(Int(age))s old): \(text)")
                    continue
                }
            }

            mirrorLogger.info("[Mirroring] Speaking: \(text)")
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
    @StateObject private var metricConfig = MetricConfigStore()
    @StateObject private var userSettings = UserSettingsStore()

    @State private var importedFileURL: URL?

    var body: some Scene {
        WindowGroup {
            ContentView(routeStore: routeStore, rideStore: rideStore, metricConfig: metricConfig, userSettings: userSettings)
                .onAppear {
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                    UnitState.shared.preferences = userSettings.settings.unitPreferences
                }
                .onChange(of: userSettings.settings.unitPreferences) { _, newValue in
                    UnitState.shared.preferences = newValue
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
