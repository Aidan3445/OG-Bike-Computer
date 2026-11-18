//
//  AltimeterReader.swift
//  OG Bike Computer Watch App
//

import CoreMotion

/// Streams the barometer's relative altitude on the main queue. Debug builds
/// with diagnostics on also stream absolute altitude, for the trace only.
final class AltimeterReader {
    static var isAvailable: Bool { CMAltimeter.isRelativeAltitudeAvailable() }

    private let relative = CMAltimeter()
    private(set) var isRunning = false
    #if DEBUG
        private let absolute = CMAltimeter()
    #endif

    /// Returns false when there's no barometer or it's already running.
    @discardableResult
    func start(
        onReading: @escaping (_ relativeAltitude: Double, _ timestamp: TimeInterval) -> Void,
        onAbsolute: @escaping (CMAbsoluteAltitudeData) -> Void
    ) -> Bool {
        guard Self.isAvailable, !isRunning else { return false }
        isRunning = true
        relative.startRelativeAltitudeUpdates(to: .main) { data, _ in
            guard let data else { return }
            onReading(data.relativeAltitude.doubleValue, data.timestamp)
        }
        #if DEBUG
            if DiagnosticsLog.isEnabled, CMAltimeter.isAbsoluteAltitudeAvailable() {
                absolute.startAbsoluteAltitudeUpdates(to: .main) { data, _ in
                    guard let data else { return }
                    onAbsolute(data)
                }
            }
        #endif
        return true
    }

    func stop() {
        guard isRunning else { return }
        relative.stopRelativeAltitudeUpdates()
        #if DEBUG
            absolute.stopAbsoluteAltitudeUpdates()
        #endif
        isRunning = false
    }
}
