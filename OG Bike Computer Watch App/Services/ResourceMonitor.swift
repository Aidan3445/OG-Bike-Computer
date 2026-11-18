//
//  ResourceMonitor.swift
//  OG Bike Computer Watch App
//

import Darwin
import Foundation
import os

/// Logs memory and CPU through a ride. A memory kill leaves nothing the app
/// can read afterwards, so the event log has to show the climb on the way up.
final class ResourceMonitor {
    static let shared = ResourceMonitor()

    /// Seconds between samples. Every sample logs while memory is low.
    static let sampleInterval: TimeInterval = 5
    /// Samples between log lines while memory is fine.
    static let samplesPerLog = 6
    /// Headroom (MB) before the memory limit under which every sample logs.
    static let lowHeadroomMB = 25.0

    /// How often the map views rebuilt since the last log line.
    private var routeMapBodies = 0
    private var freeRideMapBodies = 0

    func noteRouteMapBody() { routeMapBodies += 1 }
    func noteFreeRideMapBody() { freeRideMapBodies += 1 }

    private weak var workout: WorkoutManager?
    private var timer: Timer?
    private var pressureSource: DispatchSourceMemoryPressure?
    private var sampleCount = 0
    private var lastCPU: TimeInterval?
    private var lastSampleAt: Date?
    private var peakFootprint: UInt64 = 0

    func start(workout: WorkoutManager) {
        self.workout = workout
        log(reason: "launch")

        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: Self.sampleInterval, repeats: true) {
            [weak self] _ in
            self?.sample()
        }

        let source = DispatchSource.makeMemoryPressureSource(eventMask: [.warning, .critical], queue: .main)
        source.setEventHandler { [weak self, weak source] in
            guard let event = source?.data else { return }
            self?.log(reason: event.contains(.critical) ? "pressure-critical" : "pressure-warning")
        }
        source.resume()
        pressureSource = source
    }

    private func sample() {
        sampleCount += 1
        let lowHeadroom = Self.headroomMB().map { $0 < Self.lowHeadroomMB } ?? false
        guard lowHeadroom || sampleCount % Self.samplesPerLog == 0 else { return }
        log(reason: lowHeadroom ? "low" : "sample")
    }

    private func log(reason: String) {
        let now = Date()
        let footprint = Self.footprint()
        if let footprint, footprint > peakFootprint { peakFootprint = footprint }

        let cpuTime = Self.cpuTime()
        var cpuPercent: Double?
        if let lastCPU, let lastSampleAt, now.timeIntervalSince(lastSampleAt) > 0 {
            cpuPercent = (cpuTime - lastCPU) / now.timeIntervalSince(lastSampleAt) * 100
        }
        lastCPU = cpuTime
        lastSampleAt = now

        let fields = [
            "reason=\(reason)",
            "footprint=\(Self.mb(footprint))MB",
            "peak=\(Self.mb(peakFootprint))MB",
            "headroom=\(Self.headroomMB().map { String(format: "%.1f", $0) } ?? "-")MB",
            "cpu=\(cpuPercent.map { String(format: "%.0f", $0) } ?? "-")%",
            "routeMapBodies=\(routeMapBodies)",
            "freeRideMapBodies=\(freeRideMapBodies)",
            "riding=\(workout?.isActive ?? false)",
            "trail=\(workout?.recordedLocations.count ?? 0)",
        ]
        routeMapBodies = 0
        freeRideMapBodies = 0
        DiagnosticsLog.event("Memory", fields.joined(separator: " "))
    }

    // MARK: - Readings

    /// What the memory limit is measured against.
    private static func footprint() -> UInt64? {
        var info = task_vm_info_data_t()
        var count = mach_msg_type_number_t(
            MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : nil
    }

    /// How much more the app can use before the watch kills it.
    private static func headroomMB() -> Double? {
        let available = os_proc_available_memory()
        return available > 0 ? Double(available) / 1_048_576 : nil
    }

    /// User and system CPU seconds used since launch.
    private static func cpuTime() -> TimeInterval {
        var usage = rusage()
        guard getrusage(RUSAGE_SELF, &usage) == 0 else { return 0 }
        func seconds(_ t: timeval) -> TimeInterval {
            TimeInterval(t.tv_sec) + TimeInterval(t.tv_usec) / 1_000_000
        }
        return seconds(usage.ru_utime) + seconds(usage.ru_stime)
    }

    private static func mb(_ bytes: UInt64?) -> String {
        bytes.map { String(format: "%.1f", Double($0) / 1_048_576) } ?? "-"
    }
}
