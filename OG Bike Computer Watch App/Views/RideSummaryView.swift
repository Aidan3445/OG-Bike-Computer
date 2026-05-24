//
//  RideSummaryView.swift
//  OG Bike Computer Watch App
//
//  Created by Aidan Weinberg on 3/31/26.
//

import SwiftUI
import WatchKit

/// Transient summary captured at ride end, shown immediately while background processing runs.
struct WatchRideSummary {
    let distance: Double       // meters
    let movingTime: TimeInterval
    let elapsedTime: TimeInterval
    let avgSpeed: Double       // m/s
    let maxSpeed: Double       // m/s
    let elevationGain: Double  // meters (live estimate)
    let calories: Double
    let avgHeartRate: Double
    let maxHeartRate: Double
    let avgPower: Double
    let maxPower: Double
    /// When true, the summary represents a held (paused-and-saved) ride
    /// rather than a fully ended ride — shown with orange + hand icon.
    var isHeld: Bool = false
}

struct RideSummaryView: View {
    let summary: WatchRideSummary
    var onDismiss: () -> Void

    @State private var extendedSession: WKExtendedRuntimeSession?

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                // Header
                Image(systemName: summary.isHeld ? "hand.raised.fill" : "flag.checkered")
                    .font(.system(size: 32))
                    .foregroundStyle(summary.isHeld ? .orange : .green)

                Text(summary.isHeld ? "Held Ride" : "Ride Complete")
                    .font(.headline)

                Divider()

                // Stats grid
                VStack(spacing: 8) {
                    statRow("Distance", value: formatDistance(summary.distance))
                    statRow("Moving Time", value: formatTime(summary.movingTime))
                    statRow("Avg Speed", value: formatSpeed(summary.avgSpeed))
                    statRow("Max Speed", value: formatSpeed(summary.maxSpeed))

                    if summary.elevationGain > 0 {
                        statRow("Elevation Gain", value: formatElevation(summary.elevationGain))
                    }
                    if summary.calories > 0 {
                        statRow("Calories", value: "\(Int(summary.calories))")
                    }
                    if summary.avgHeartRate > 0 {
                        statRow("Avg HR", value: "\(Int(summary.avgHeartRate)) bpm")
                    }
                    if summary.maxHeartRate > 0 {
                        statRow("Max HR", value: "\(Int(summary.maxHeartRate)) bpm")
                    }
                    if summary.avgPower > 0 {
                        statRow("Avg Power", value: "\(Int(summary.avgPower)) W")
                    }
                    if summary.maxPower > 0 {
                        statRow("Max Power", value: "\(Int(summary.maxPower)) W")
                    }
                }

                Divider()

                Button("Done") {
                    onDismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(summary.isHeld ? .orange : .green)

                if summary.isHeld {
                    Text("Resume from the route list or your phone.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
        }
        .onAppear {
            let session = WKExtendedRuntimeSession()
            session.start()
            extendedSession = session
        }
        .onDisappear {
            extendedSession?.invalidate()
            extendedSession = nil
        }
    }

    // MARK: - Helpers

    private func statRow(_ label: String, value: String) -> some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.system(.body, design: .rounded).weight(.medium))
                .monospacedDigit()
        }
    }

    private func formatDistance(_ meters: Double) -> String {
        let prefs = UnitState.shared.preferences
        if prefs.distance == .miles {
            let miles = meters / 1609.34
            return String(format: "%.1f mi", miles)
        } else {
            let km = meters / 1000
            return String(format: "%.1f km", km)
        }
    }

    private func formatSpeed(_ mps: Double) -> String {
        let prefs = UnitState.shared.preferences
        if prefs.speed == .mph {
            return String(format: "%.1f mph", mps * 2.23694)
        } else {
            return String(format: "%.1f km/h", mps * 3.6)
        }
    }

    private func formatElevation(_ meters: Double) -> String {
        let prefs = UnitState.shared.preferences
        if prefs.elevation == .feet {
            return String(format: "%.0f ft", meters * 3.28084)
        } else {
            return String(format: "%.0f m", meters)
        }
    }

    private func formatTime(_ seconds: TimeInterval) -> String {
        let h = Int(seconds) / 3600
        let m = (Int(seconds) % 3600) / 60
        let s = Int(seconds) % 60
        if h > 0 {
            return String(format: "%d:%02d:%02d", h, m, s)
        } else {
            return String(format: "%d:%02d", m, s)
        }
    }
}
