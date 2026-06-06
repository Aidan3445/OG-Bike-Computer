//
//  RideLiveActivityWidget.swift
//  OG Bike Computer Widget
//
//  Created by Aidan Weinberg on 3/28/26.
//

#if canImport(ActivityKit)
import ActivityKit
import AppIntents
import SwiftUI
import WidgetKit

@main
struct RideLiveActivityWidget: WidgetBundle {
    var body: some Widget {
        RideLiveActivity()
    }
}

// MARK: - Status Badge

/// Maps a ride lifecycle status to the icon / tint / label triple the various
/// live activity surfaces show when the ride isn't actively in progress.
private struct StatusBadge {
    let icon: String
    let tint: Color
    let label: String

    init(status: RideStatus) {
        switch status {
        case .completed:
            icon = "checkmark.circle.fill"
            tint = Theme.primaryLight
            label = "Ride Complete"
        case .held:
            icon = "hand.raised.fill"
            tint = .orange
            label = "Ride On Hold"
        case .discarded:
            icon = "trash.fill"
            tint = .red
            label = "Ride Discarded"
        case .active, .inactive:
            icon = "bicycle"
            tint = Theme.primaryLight
            label = "No Active Ride"
        }
    }

    /// Compact-trailing badge: nil when the ride is active (so the caller can
    /// fall back to nav / distance) or `label` is short enough for the pill.
    static func compact(for status: RideStatus) -> (label: String, tint: Color)? {
        switch status {
        case .completed: return ("Done", Theme.primaryLight)
        case .held: return ("Held", .orange)
        case .discarded: return ("Discarded", .red)
        case .active, .inactive: return nil
        }
    }
}

/// Compact-leading / minimal icon shared between two Dynamic Island regions:
/// show the terminal-status glyph when set, otherwise the upcoming-turn arrow,
/// otherwise the bike fallback.
@ViewBuilder
private func navIconForCompact(context: ActivityViewContext<RideActivityAttributes>) -> some View {
    let status = context.state.status
    switch status {
    case .completed:
        Image(systemName: "checkmark.circle.fill").foregroundStyle(Theme.primaryLight)
    case .held:
        Image(systemName: "hand.raised.fill").foregroundStyle(.orange)
    case .discarded:
        Image(systemName: "trash.fill").foregroundStyle(.red)
    case .active, .inactive:
        if let icon = context.state.nextTurnIcon ?? context.state.nextTurnDirection.map({ turnIcon($0) }) {
            Image(systemName: icon).foregroundStyle(Theme.primaryLight)
        } else {
            Image(systemName: "bicycle").foregroundStyle(Theme.primaryLight)
        }
    }
}

// MARK: - Theme

private enum Theme {
    static let primary = Color(red: 0.62, green: 0.38, blue: 0.93)        // vivid purple
    static let primaryLight = Color(red: 0.78, green: 0.58, blue: 1.0)    // lavender
    static let primaryDeep = Color(red: 0.38, green: 0.18, blue: 0.62)    // deep purple
    static let accent = Color(red: 0.55, green: 0.85, blue: 1.0)          // ice cyan (for nav)

    static let lockBackground = LinearGradient(
        colors: [
            Color(red: 0.16, green: 0.08, blue: 0.28),
            Color(red: 0.10, green: 0.05, blue: 0.20),
            Color(red: 0.18, green: 0.08, blue: 0.32)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )
}

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen / Banner
            LockScreenView(context: context)
                .widgetURL(URL(string: "ogbikecomputer://ridecontrol"))
                .activityBackgroundTint(Color(red: 0.10, green: 0.05, blue: 0.20))
                .activitySystemActionForegroundColor(Theme.primaryLight)
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 5) {
                            Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.primaryLight)
                            Text(formatDistance(context.state.totalDistance, imperial: context.attributes.isImperial))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                        }
                        HStack(spacing: 5) {
                            Image(systemName: "speedometer")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.secondary)
                            Text(formatSpeed(context.state.averageSpeed, imperial: context.attributes.isImperial))
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                                .monospacedDigit()
                        }
                    }
                    .padding(.leading, 6)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 4) {
                        HStack(spacing: 5) {
                            Text(formatDuration(context.state.movingTime, hideSeconds: false))
                                .font(.body.weight(.semibold))
                                .monospacedDigit()
                                .foregroundStyle(.white)
                            Image(systemName: "timer")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(Theme.primaryLight)
                        }
                        if let hr = context.state.heartRate, hr > 0 {
                            HStack(spacing: 5) {
                                Text("\(Int(hr))")
                                    .font(.subheadline.weight(.medium))
                                    .monospacedDigit()
                                    .foregroundStyle(.white.opacity(0.9))
                                Image(systemName: "heart.fill")
                                    .font(.caption2)
                                    .foregroundStyle(.pink)
                            }
                        } else {
                            HStack(spacing: 5) {
                                Text(formatSpeed(context.state.currentSpeed, imperial: context.attributes.isImperial))
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                                    .monospacedDigit()
                                Image(systemName: "gauge.with.dots.needle.bottom.50percent")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.trailing, 6)
                }
                DynamicIslandExpandedRegion(.center) {
                    if context.state.isOffRoute {
                        HStack(spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(.orange)
                            Text("Off Route")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.orange)
                            if let dist = context.state.distanceOffRoute {
                                Text("+\(formatTurnDistance(dist, imperial: context.attributes.isImperial))")
                                    .font(.footnote.weight(.medium))
                                    .foregroundStyle(.orange.opacity(0.85))
                                    .monospacedDigit()
                            }
                        }
                    } else if let dir = context.state.nextTurnDirection {
                        HStack(spacing: 6) {
                            Image(systemName: context.state.nextTurnIcon ?? turnIcon(dir))
                                .font(.subheadline.weight(.bold))
                                .foregroundStyle(Theme.primaryLight)
                            Text(dir.capitalized)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                            if let dist = context.state.distanceToNextTurn {
                                Text("· \(formatTurnDistance(dist, imperial: context.attributes.isImperial))")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.primaryLight.opacity(0.85))
                                    .monospacedDigit()
                            }
                        }
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    let status = context.state.status
                    if status == .active {
                        if let cue = context.state.nextTurnCue, !cue.isEmpty {
                            MarqueeText(text: cue, font: .footnote)
                                .foregroundStyle(.white.opacity(0.7))
                                .frame(maxWidth: .infinity)
                                .padding(.horizontal, 12)
                                .padding(.bottom, 2)
                        }
                    } else {
                        let badge = StatusBadge(status: status)
                        HStack(spacing: 8) {
                            Image(systemName: badge.icon)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(badge.tint)
                            Text(badge.label)
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal, 12)
                        .padding(.bottom, 4)
                    }
                }
            } compactLeading: {
                navIconForCompact(context: context)
            } compactTrailing: {
                let status = context.state.status
                if let badge = StatusBadge.compact(for: status) {
                    Text(badge.label)
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(badge.tint)
                } else if let dist = context.state.distanceToNextTurn {
                    Text(formatTurnDistance(dist, imperial: context.attributes.isImperial))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryLight)
                } else {
                    Text(formatDistanceCompact(context.state.totalDistance, imperial: context.attributes.isImperial))
                        .font(.caption.weight(.semibold))
                        .monospacedDigit()
                        .foregroundStyle(Theme.primaryLight)
                }
            } minimal: {
                navIconForCompact(context: context)
            }
            .widgetURL(URL(string: "ogbikecomputer://ridecontrol"))
            .keylineTint(Theme.primary)
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<RideActivityAttributes>
    @Environment(\.isLuminanceReduced) var isLuminanceReduced

    private var state: RideActivityAttributes.ContentState { context.state }
    private var isImperial: Bool { context.attributes.isImperial }
    private var statSlots: [String] { context.attributes.statSlots }
    private var hasNav: Bool { state.nextTurnDirection != nil || state.isOffRoute }
    private var isActive: Bool { state.status == .active }
    private var isCompleted: Bool { state.status == .completed }
    private var isHeld: Bool { state.status == .held }
    private var isDiscarded: Bool { state.status == .discarded }

    var body: some View {
        Group {
            if isActive {
                activeBody
            } else {
                inactiveBody
            }
        }
        .background {
            ZStack {
                Theme.lockBackground
                RadialGradient(
                    colors: [Theme.primary.opacity(0.35), .clear],
                    center: .topTrailing,
                    startRadius: 0,
                    endRadius: 180
                )
                .blendMode(.plusLighter)
            }
        }
    }

    // MARK: - Inactive / Completed / Held state

    /// Display copy for the inactive/completed/held lock-screen banner.
    /// Computed once per render so the body doesn't fan out into three
    /// parallel switches on `state.status`.
    private struct Display {
        let icon: String
        let title: String
        let subtitle: String
        /// Tint used for accents (chevron, shadow).
        let tint: Color
        /// Gradient stops for the leading circle. Each status gets its own
        /// pair so completed/held/discarded read at a glance.
        let circleGradient: [Color]
        let showChevron: Bool
    }

    private var display: Display {
        switch state.status {
        case .completed:
            return .init(icon: "checkmark", title: "Ride Complete",
                         subtitle: "Tap to open ride details",
                         tint: Theme.primaryLight,
                         circleGradient: [Theme.primaryLight, Theme.primary],
                         showChevron: true)
        case .held:
            return .init(icon: "hand.raised.fill", title: "Ride On Hold",
                         subtitle: "Resume from the watch or rides list",
                         tint: .orange,
                         circleGradient: [Color.orange.opacity(0.9), Color.orange],
                         showChevron: true)
        case .discarded:
            return .init(icon: "trash.fill", title: "Ride Discarded",
                         subtitle: "Short ride wasn't saved",
                         tint: .red,
                         circleGradient: [Color.red.opacity(0.85), Color.red],
                         showChevron: false)
        case .active, .inactive:
            return .init(icon: "bicycle", title: "No Active Ride",
                         subtitle: "Start a ride from the app or watch",
                         tint: Theme.primaryLight,
                         circleGradient: [Theme.primaryLight, Theme.primary],
                         showChevron: false)
        }
    }

    private var inactiveBody: some View {
        let d = display
        return HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: d.circleGradient,
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 36, height: 36)
                    .shadow(color: d.tint.opacity(0.6), radius: 5, y: 1)
                Image(systemName: d.icon)
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(d.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                Text(d.subtitle)
                    .font(.caption2)
                    .foregroundStyle(.white.opacity(0.65))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            if d.showChevron {
                Image(systemName: "chevron.right")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(d.tint)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var activeBody: some View {
        VStack(spacing: 6) {
            // Header row: brand mark + status pill (only when no nav — nav banner takes its place)
            if !isLuminanceReduced && !hasNav {
                headerBar
            }

            // Nav banner (only when active) — includes status pill in trailing edge
            if !isLuminanceReduced, hasNav {
                navBanner
            }

            // Stats grid — configurable 2 rows of 3
            statsGrid

            // Route remaining row (only when no nav banner showing — nav banner has its own context)
            if !isLuminanceReduced, !hasNav, let remaining = state.routeDistanceRemaining {
                HStack(spacing: 6) {
                    Image(systemName: "flag.checkered")
                        .font(.caption2)
                        .foregroundStyle(Theme.primaryLight.opacity(0.8))
                    Text("\(formatDistance(remaining, imperial: isImperial)) to finish")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.7))
                        .monospacedDigit()
                    Spacer()
                }
                .padding(.horizontal, 2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    // MARK: - Header

    private var headerBar: some View {
        HStack(spacing: 8) {
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [Theme.primaryLight, Theme.primary],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 22, height: 22)
                    .shadow(color: Theme.primary.opacity(0.6), radius: 4, y: 1)
                Image(systemName: "bicycle")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(.white)
            }
            Text("Riding")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.white.opacity(0.95))
            Spacer()
            statusPill
        }
    }

    @ViewBuilder
    private var statusPill: some View {
        if state.isPaused {
            pill(text: "PAUSED", icon: "pause.fill", color: .yellow)
        } else if state.isAutoPaused {
            pill(text: "AUTO PAUSED", icon: "pause.circle.fill", color: .yellow)
        } else {
            HStack(spacing: 5) {
                Circle()
                    .fill(.green)
                    .frame(width: 6, height: 6)
                    .shadow(color: .green.opacity(0.8), radius: 3)
                Text("LIVE")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.white.opacity(0.9))
                    .tracking(0.5)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(
                Capsule()
                    .fill(.white.opacity(0.08))
                    .overlay(Capsule().stroke(.white.opacity(0.15), lineWidth: 0.5))
            )
        }
    }

    private func pill(text: String, icon: String, color: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2.weight(.bold))
            Text(text)
                .font(.caption2.weight(.bold))
                .tracking(0.5)
        }
        .foregroundStyle(color)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            Capsule()
                .fill(color.opacity(0.15))
                .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 0.5))
        )
    }

    // MARK: - Nav Banner

    @ViewBuilder
    private var navBanner: some View {
        HStack(spacing: 10) {
            if state.isOffRoute {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color.orange.opacity(0.25))
                        .frame(width: 28, height: 28)
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.body.weight(.bold))
                        .foregroundStyle(.orange)
                }
                VStack(alignment: .leading, spacing: 1) {
                    Text("Off Route")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    if let dist = state.distanceOffRoute {
                        Text("+\(formatTurnDistance(dist, imperial: isImperial)) from route")
                            .font(.caption2)
                            .foregroundStyle(.orange.opacity(0.8))
                    }
                }
                Spacer()
                statusPill
            } else if let dir = state.nextTurnDirection {
                ZStack {
                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [Theme.primary.opacity(0.4), Theme.primaryDeep.opacity(0.3)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .frame(width: 28, height: 28)
                    Image(systemName: state.nextTurnIcon ?? turnIcon(dir))
                        .font(.body.weight(.bold))
                        .foregroundStyle(Theme.primaryLight)
                }
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 5) {
                        Text(dir.capitalized)
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.white)
                        if let dist = state.distanceToNextTurn {
                            Text("· \(formatTurnDistance(dist, imperial: isImperial))")
                                .font(.caption)
                                .foregroundStyle(Theme.primaryLight)
                                .monospacedDigit()
                        }
                    }
                    if let cue = state.nextTurnCue, !cue.isEmpty {
                        MarqueeText(text: cue, font: .caption2)
                            .foregroundStyle(.white.opacity(0.6))
                    }
                }
                Spacer()
                statusPill
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(Theme.primary.opacity(0.25), lineWidth: 0.5)
                )
        )
    }

    // MARK: - Configurable Stats Grid

    @ViewBuilder
    private var statsGrid: some View {
        let topRow = Array(statSlots.prefix(3))
        let bottomRow = Array(statSlots.dropFirst(3).prefix(3))

        VStack(spacing: 4) {
            HStack(spacing: 4) {
                ForEach(Array(topRow.enumerated()), id: \.offset) { _, slot in
                    statCell(for: slot)
                }
            }
            if !bottomRow.isEmpty {
                HStack(spacing: 4) {
                    ForEach(Array(bottomRow.enumerated()), id: \.offset) { _, slot in
                        statCell(for: slot)
                    }
                }
            }
        }
    }

    private func statCell(for slotRawValue: String) -> some View {
        let label = metricLabel(slotRawValue)
        let value = resolveMetricValue(slotRawValue)
        let icon = metricIcon(slotRawValue)
        let tint = metricTint(slotRawValue)

        return VStack(spacing: 1) {
            HStack(spacing: 3) {
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(tint)
                Text(label)
                    .font(.system(size: 8, weight: .bold))
                    .tracking(0.4)
                    .foregroundStyle(.white.opacity(0.55))
            }
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(.white)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
        .background(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.white.opacity(0.06))
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(.white.opacity(0.08), lineWidth: 0.5)
                )
        )
    }

    /// Resolve a metric raw value to its display string from ContentState.
    private func resolveMetricValue(_ rawValue: String) -> String {
        let hideSeconds = isLuminanceReduced

        switch rawValue {
        case "speed":
            return formatSpeed(state.currentSpeed, imperial: isImperial)
        case "averageSpeed":
            return formatSpeed(state.averageSpeed, imperial: isImperial)
        case "maxSpeed":
            guard let v = state.maxSpeed, v > 0 else { return "--" }
            return formatSpeed(v, imperial: isImperial)
        case "distance":
            return formatDistance(state.totalDistance, imperial: isImperial)
        case "distanceRemaining":
            guard let v = state.routeDistanceRemaining else { return "--" }
            return formatDistance(v, imperial: isImperial)
        case "elapsedTime":
            return formatDuration(state.elapsedTime, hideSeconds: hideSeconds)
        case "movingTime":
            return formatDuration(state.movingTime, hideSeconds: hideSeconds)
        case "heartRate":
            guard let v = state.heartRate, v > 0 else { return "--" }
            return "\(Int(v))"
        case "averageHeartRate":
            guard let v = state.averageHeartRate, v > 0 else { return "--" }
            return "\(Int(v))"
        case "maxHeartRate":
            guard let v = state.maxHeartRate, v > 0 else { return "--" }
            return "\(Int(v))"
        case "calories":
            guard let v = state.activeCalories, v > 0 else { return "--" }
            return "\(Int(v))"
        case "currentElevation":
            guard let v = state.currentElevation else { return "--" }
            return formatElevation(v, imperial: isImperial)
        case "elevationGain":
            guard let v = state.elevationGain, v > 0 else { return "--" }
            return formatElevation(v, imperial: isImperial)
        case "elevationLoss":
            guard let v = state.elevationLoss, v > 0 else { return "--" }
            return formatElevation(v, imperial: isImperial)
        case "highestElevation":
            guard let v = state.highestElevation else { return "--" }
            return formatElevation(v, imperial: isImperial)
        case "grade":
            guard let v = state.currentGrade, v != 0 else { return "--" }
            return String(format: "%.1f%%", v)
        case "powerEstimate":
            guard let v = state.estimatedPower, v > 0 else { return "--" }
            return "\(Int(v))W"
        case "nextTurnDistance":
            guard let v = state.distanceToNextTurn else { return "--" }
            return formatTurnDistance(v, imperial: isImperial)
        case "nextTurnDirection":
            return state.nextTurnDirection ?? "--"
        default:
            return "--"
        }
    }
}

// MARK: - Formatting Helpers

private func formatDistance(_ meters: Double, imperial: Bool) -> String {
    if imperial {
        let miles = meters / 1609.34
        return String(format: "%.1f mi", miles)
    } else {
        let km = meters / 1000
        return String(format: "%.1f km", km)
    }
}

/// Mirrors the watch's `formatTurnDistance` — steps down through tenths
/// before switching to feet/meters so short turn distances aren't shown as "0.1 mi".
private func formatTurnDistance(_ meters: Double, imperial: Bool) -> String {
    if imperial {
        let miles = meters / 1609.34
        if miles >= 1.0 {
            return String(format: "%.1f mi", miles)
        }
        if miles >= 0.1 {
            let tenths = (miles * 10).rounded() / 10
            return String(format: "%.1f mi", tenths)
        }
        let feet = Int(meters * 3.28084)
        return "\((feet / 50) * 50) ft"
    } else {
        let km = meters / 1000
        if km >= 1.0 {
            return String(format: "%.1f km", km)
        }
        if km >= 0.1 {
            let tenths = (km * 10).rounded() / 10
            return String(format: "%.1f km", tenths)
        }
        let m = Int(meters)
        return "\((m / 50) * 50) m"
    }
}

private func formatDistanceCompact(_ meters: Double, imperial: Bool) -> String {
    if imperial {
        let miles = meters / 1609.34
        return String(format: "%.1f", miles)
    } else {
        let km = meters / 1000
        return String(format: "%.1f", km)
    }
}

private func formatSpeed(_ mps: Double, imperial: Bool) -> String {
    if imperial {
        return String(format: "%.1f mph", mps * 2.23694)
    } else {
        return String(format: "%.1f km/h", mps * 3.6)
    }
}

private func formatDuration(_ seconds: TimeInterval, hideSeconds: Bool) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    if hideSeconds {
        // Always-on display dim mode: omit seconds
        if h > 0 {
            return String(format: "%d:%02d", h, m)
        }
        return "\(m) min"
    }
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
}

private func formatElevation(_ meters: Double, imperial: Bool) -> String {
    if imperial {
        return "\(Int(meters * 3.28084)) ft"
    }
    return "\(Int(meters)) m"
}

/// Map MetricType raw values to display labels (avoids depending on MetricType in widget target).
private func metricLabel(_ rawValue: String) -> String {
    switch rawValue {
    case "speed": return "SPEED"
    case "averageSpeed": return "AVG SPEED"
    case "maxSpeed": return "MAX SPEED"
    case "distance": return "DISTANCE"
    case "distanceRemaining": return "REMAINING"
    case "elapsedTime": return "ELAPSED"
    case "movingTime": return "MOVING"
    case "heartRate": return "HR"
    case "averageHeartRate": return "AVG HR"
    case "maxHeartRate": return "MAX HR"
    case "calories": return "CAL"
    case "currentElevation": return "ELEVATION"
    case "elevationGain": return "ELEV GAIN"
    case "elevationLoss": return "ELEV LOSS"
    case "highestElevation": return "HIGH ELEV"
    case "grade": return "GRADE"
    case "powerEstimate": return "POWER"
    case "nextTurnDistance": return "NEXT TURN"
    case "nextTurnDirection": return "TURN DIR"
    case "heading": return "HEADING"
    default: return rawValue.uppercased()
    }
}

private func metricIcon(_ rawValue: String) -> String {
    switch rawValue {
    case "speed", "averageSpeed", "maxSpeed": return "speedometer"
    case "distance": return "point.topleft.down.to.point.bottomright.curvepath"
    case "distanceRemaining": return "flag.checkered"
    case "elapsedTime", "movingTime": return "timer"
    case "heartRate", "averageHeartRate", "maxHeartRate": return "heart.fill"
    case "calories": return "flame.fill"
    case "currentElevation", "highestElevation": return "mountain.2.fill"
    case "elevationGain": return "arrow.up.right"
    case "elevationLoss": return "arrow.down.right"
    case "grade": return "angle"
    case "powerEstimate": return "bolt.fill"
    case "nextTurnDistance", "nextTurnDirection": return "arrow.triangle.turn.up.right.diamond.fill"
    case "heading": return "location.north.fill"
    default: return "circle.fill"
    }
}

private func metricTint(_ rawValue: String) -> Color {
    switch rawValue {
    case "heartRate", "averageHeartRate", "maxHeartRate": return .pink
    case "calories": return .orange
    case "powerEstimate": return .yellow
    case "elevationGain": return .green
    case "elevationLoss": return .blue
    case "grade": return .mint
    default: return Theme.primaryLight
    }
}

private func turnIcon(_ direction: String) -> String {
    let lower = direction.lowercased()
    if lower.contains("sharp") && lower.contains("left") { return "arrow.turn.up.left" }
    if lower.contains("sharp") && lower.contains("right") { return "arrow.turn.up.right" }
    if lower.contains("slight") && lower.contains("left") { return "arrow.up.left" }
    if lower.contains("slight") && lower.contains("right") { return "arrow.up.right" }
    if lower.contains("left") { return "arrow.left" }
    if lower.contains("right") { return "arrow.right" }
    if lower.contains("u-turn") || lower.contains("u turn") { return "arrow.uturn.down" }
    if lower.contains("straight") || lower.contains("continue") { return "arrow.up" }
    return "arrow.triangle.turn.up.right.diamond"
}
#endif
