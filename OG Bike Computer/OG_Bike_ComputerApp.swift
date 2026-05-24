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
import UserNotifications
#if canImport(ActivityKit)
import ActivityKit
#endif

private let mirrorLogger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "Mirroring")

class AppDelegate: NSObject, UIApplicationDelegate {
    private let locationManager = CLLocationManager()
    private let healthStore = HKHealthStore()
    private var mirroredSession: HKWorkoutSession?
    /// Tracks the previous showTurnNotifications setting so we can request
    /// permission / clear pending notifications when it toggles mid-ride.
    private var lastShowTurnNotifications: Bool = false
    private var phoneAlertObserver: NSObjectProtocol?

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        ConnectivityManager.shared.activate()
        // Install the WCSession→PhoneSpeechPlayer bridge for voice alerts.
        // Must be done after activate() so the callback is wired before
        // the first message can arrive.
        PhoneAlertReceiver.shared.install()
        locationManager.requestWhenInUseAuthorization()

        let warmup = MKMapView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))
        _ = warmup.region

        // Configure audio session category ONCE at launch via
        // PhoneSpeechPlayer (single source of truth). This registers us as a
        // ducking session before any workout starts — if we wait until the
        // first speech arrives, the category change itself causes a full
        // interruption to the music app instead of a duck.
        PhoneSpeechPlayer.shared.configureAudioSessionIfNeeded()

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
            RideSessionManager.shared.mirroredSession = mirroredSession
            mirroredSession.delegate = self
            // AVSpeechSynthesizer is not thread-safe — reset on main
            DispatchQueue.main.async {
                PhoneSpeechPlayer.shared.resetSession()
                self?.startPhoneAlerts()
            }
        }

        // Observe phone alert preference changes so we can restart/stop
        // Live Activity mid-ride when user toggles the setting
        phoneAlertObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.handlePhoneAlertPrefsChange()
        }

        return true
    }

    private func handlePhoneAlertPrefsChange() {
        // Only act when a ride is active.
        guard mirroredSession != nil else { return }

        let prefs = loadPhoneAlertPreferences()
        let newValue = prefs.showTurnNotifications
        guard newValue != lastShowTurnNotifications else { return }

        let oldValue = lastShowTurnNotifications
        lastShowTurnNotifications = newValue
        print("[AppDelegate] showTurnNotifications changed: \(oldValue) → \(newValue)")

        // Live Activity is always running during a ride; only the banner-
        // notification side effect toggles here.
        if oldValue {
            TurnNotificationManager.shared.clearAll()
        }
        if newValue {
            TurnNotificationManager.shared.requestPermission()
        }
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

        RideSessionManager.shared.handleSessionStateChange(to: toState)

        if toState == .ended || toState == .stopped {
            DispatchQueue.main.async {
                PhoneSpeechPlayer.shared.stopImmediately()
                self.stopPhoneAlerts()
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
        RideSessionManager.shared.mirroredSession = nil
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
                  let type = payload["type"] else {
                continue
            }

            // Voice alerts no longer flow through HK mirroring — they're
            // on WCSession now via PhoneAlertReceiver (plan §1, §2.4). The
            // HK channel is reserved for telemetry/ping only. Stale-drop
            // threshold therefore uses the looser 10s for everything.
            if let tsString = payload["ts"], let ts = Double(tsString) {
                let age = now - ts
                if age > 10 {
                    mirrorLogger.info("[Mirroring] Discarding stale \(type) message (\(String(format: "%.1f", age))s old)")
                    continue
                }
            }

            switch type {
            case "telemetry":
                PhoneTelemetryStore.shared.update(from: payload)
                #if canImport(ActivityKit)
                DispatchQueue.main.async {
                    LiveActivityManager.shared.update(from: payload)
                    RideSessionManager.shared.writeMovingTimeToAppGroup(
                        PhoneTelemetryStore.shared.movingTime
                    )
                    RideSessionManager.shared.processPendingWidgetCommand()
                }
                #endif

            case "ping":
                // Connection health check from Watch — no action needed.
                // Success/failure of the send on Watch side is what matters.
                break

            default:
                break
            }
        }
    }

    // MARK: - Phone Alert Helpers

    private func startPhoneAlerts() {
        let phonePrefs = loadPhoneAlertPreferences()
        lastShowTurnNotifications = phonePrefs.showTurnNotifications
        print("[AppDelegate] startPhoneAlerts called: showTurnNotifications=\(phonePrefs.showTurnNotifications)")

        // ALWAYS start a Live Activity when the mirrored workout begins
        // (plan §2.7). The 10s HK-mirroring grace window requires the
        // companion iPhone app to start a Live Activity or risk session
        // teardown. Live Activity is now unconditional; the user
        // preference only controls additional banner notifications.
        #if canImport(ActivityKit)
        let unitPrefs = loadUnitPreferences()
        let isImperial = unitPrefs.distance == .miles
        let slots = phonePrefs.liveActivitySlots.map(\.metricType.rawValue)
        print("[AppDelegate] Starting Live Activity (imperial=\(isImperial))")
        LiveActivityManager.shared.startActivity(routeName: nil, isImperial: isImperial, statSlots: slots)
        #else
        print("[AppDelegate] ActivityKit not available on this build")
        #endif

        if phonePrefs.showTurnNotifications {
            print("[AppDelegate] Requesting Turn Notification permission")
            TurnNotificationManager.shared.requestPermission()
        }
    }

    private func stopPhoneAlerts() {
        lastShowTurnNotifications = false
        #if canImport(ActivityKit)
        LiveActivityManager.shared.endActivity()
        #endif
        TurnNotificationManager.shared.clearAll()
    }

    private func loadPhoneAlertPreferences() -> PhoneAlertPreferences {
        guard let data = UserDefaults.standard.data(forKey: "phoneAlerts"),
              let prefs = try? JSONDecoder().decode(PhoneAlertPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }

    private func loadUnitPreferences() -> UnitPreferences {
        guard let data = UserDefaults.standard.data(forKey: "unitPreferences"),
              let prefs = try? JSONDecoder().decode(UnitPreferences.self, from: data) else {
            return .default
        }
        return prefs
    }
}

@main
struct OG_Bike_ComputerApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var routeStore = RouteStore()
    @StateObject private var rideStore = RideStore()
    @StateObject private var metricConfig = MetricConfigStore()
    @StateObject private var userSettings = UserSettingsStore()
    @StateObject private var integrationSettings = IntegrationSettingsStore()

    @State private var importedFileURL: URL?
    @State private var showRideControl = false

    var body: some Scene {
        WindowGroup {
            ContentView(routeStore: routeStore, rideStore: rideStore, metricConfig: metricConfig, userSettings: userSettings, integrationSettings: integrationSettings, showRideControlFullScreen: $showRideControl)
                .onAppear {
                    RouteImportPipeline.shared.configure(routeStore: routeStore)
                    ConnectivityManager.shared.attachStores(rideStore: rideStore)
                    UnitState.shared.preferences = userSettings.settings.unitPreferences
                    userSettings.attachMetricStore(metricConfig)
                    integrationSettings.migrateHealthKitSetting(to: userSettings)
                    cachePreferencesForAppDelegate()
                    UploadManager.shared.configure(rideStore: rideStore, integrationSettings: integrationSettings)
                    UploadManager.shared.retryFailedUploads()
                    ConnectivityManager.shared.onRideReceived = { ride in
                        UploadManager.shared.handleNewRide(ride)
                    }
                    if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
                       let window = windowScene.windows.first {
                        OAuthManager.shared.setPresentationAnchor(window)
                    }
                }
                .onChange(of: userSettings.settings.unitPreferences) { _, newValue in
                    UnitState.shared.preferences = newValue
                    cachePreferencesForAppDelegate()
                }
                .onChange(of: userSettings.settings.phoneAlerts) { _, _ in
                    cachePreferencesForAppDelegate()
                }
                .onOpenURL { url in
                    if url.scheme == "ogbikecomputer" && url.host == "ridecontrol" {
                        if RideSessionManager.shared.isRideActive {
                            showRideControl = true
                        }
                    } else {
                        handleIncomingFile(url)
                    }
                }
        }
    }

    /// Cache phone alert + unit preferences to UserDefaults so the AppDelegate
    /// can access them outside the SwiftUI lifecycle (e.g. during HK mirroring callbacks).
    private func cachePreferencesForAppDelegate() {
        if let data = try? JSONEncoder().encode(userSettings.settings.phoneAlerts) {
            UserDefaults.standard.set(data, forKey: "phoneAlerts")
        }
        if let data = try? JSONEncoder().encode(userSettings.settings.unitPreferences) {
            UserDefaults.standard.set(data, forKey: "unitPreferences")
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
        let routes = RouteImportPipeline.shared.importGPX(data: data)
        if !routes.isEmpty {
            print("Imported \(routes.count) route(s) from share sheet")
            RouteImportCoordinator.shared.handle(routes)
        }
    }
}
