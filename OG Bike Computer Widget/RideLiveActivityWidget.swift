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

struct RideLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: RideActivityAttributes.self) { context in
            // Lock Screen / Banner
            LockScreenView(context: context)
                .widgetURL(URL(string: "ogbikecomputer://ridecontrol"))
        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded
                DynamicIslandExpandedRegion(.leading) {
                    VStack(alignment: .leading, spacing: 2) {
                        Label(formatDistance(context.state.totalDistance, imperial: context.attributes.isImperial), systemImage: "point.topleft.down.to.point.bottomright.curvepath")
                            .font(.caption.weight(.semibold))
                        Text(formatSpeed(context.state.averageSpeed, imperial: context.attributes.isImperial))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
                DynamicIslandExpandedRegion(.trailing) {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text(formatDuration(context.state.movingTime, hideSeconds: false))
                            .font(.caption.weight(.semibold))
                            .monospacedDigit()
                        if let hr = context.state.heartRate, hr > 0 {
                            Label("\(Int(hr))", systemImage: "heart.fill")
                                .font(.caption2)
                                .foregroundStyle(.red)
                        }
                    }
                }
                DynamicIslandExpandedRegion(.center) {
                    if let dir = context.state.nextTurnDirection {
                        HStack(spacing: 4) {
                            Image(systemName: context.state.nextTurnIcon ?? turnIcon(dir))
                                .font(.caption.weight(.bold))
                            Text(dir)
                                .font(.caption.weight(.medium))
                            if let dist = context.state.distanceToNextTurn {
                                Text("in \(formatDistance(dist, imperial: context.attributes.isImperial))")
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    } else if context.state.isOffRoute {
                        Label("Off Route", systemImage: "exclamationmark.triangle.fill")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.orange)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if let cue = context.state.nextTurnCue {
                        Text(cue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                    HStack(spacing: 8) {
                        Button(intent: PauseResumeRideIntent()) {
                            Image(systemName: context.state.isPaused ? "play.fill" : "pause.fill")
                                .font(.caption2)
                        }
                        .tint(context.state.isPaused ? .green : .yellow)

                        Button(intent: EndRideIntent()) {
                            Image(systemName: "stop.fill")
                                .font(.caption2)
                        }
                        .tint(.red)
                    }
                    .buttonStyle(.borderedProminent)
                }
            } compactLeading: {
                if let icon = context.state.nextTurnIcon ?? context.state.nextTurnDirection.map({ turnIcon($0) }) {
                    Image(systemName: icon)
                        .foregroundStyle(.cyan)
                } else {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.cyan)
                }
            } compactTrailing: {
                if let dist = context.state.distanceToNextTurn {
                    Text(formatDistance(dist, imperial: context.attributes.isImperial))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                } else {
                    Text(formatDistanceCompact(context.state.totalDistance, imperial: context.attributes.isImperial))
                        .font(.caption2.weight(.semibold))
                        .monospacedDigit()
                }
            } minimal: {
                if let icon = context.state.nextTurnIcon ?? context.state.nextTurnDirection.map({ turnIcon($0) }) {
                    Image(systemName: icon)
                        .foregroundStyle(.cyan)
                } else {
                    Image(systemName: "bicycle")
                        .foregroundStyle(.cyan)
                }
            }
            .widgetURL(URL(string: "ogbikecomputer://ridecontrol"))
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

    var body: some View {
        VStack(spacing: 6) {
            // Top bar: nav info (if route) with compact controls, or nothing
            if !isLuminanceReduced {
                if hasNav {
                    // Nav bar with compact round buttons in trailing corner
                    HStack(spacing: 0) {
                        turnNavigationContent
                        Spacer(minLength: 4)
                        compactControls
                    }
                } else {
                    // No nav — nothing up top, buttons at bottom
                    EmptyView()
                }
            }

            // Stats grid — configurable 2 rows of 3
            statsGrid

            // Route remaining (if navigating, hidden in dim mode)
            if !isLuminanceReduced, let remaining = state.routeDistanceRemaining {
                HStack {
                    Image(systemName: "flag.checkered")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    Text("\(formatDistance(remaining, imperial: isImperial)) remaining")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                }
            }

            // Full-width pill buttons only when there's NO nav (plenty of space)
            if !isLuminanceReduced && !hasNav {
                HStack(spacing: 12) {
                    Button(intent: PauseResumeRideIntent()) {
                        Label(
                            state.isPaused ? "Resume" : "Pause",
                            systemImage: state.isPaused ? "play.fill" : "pause.fill"
                        )
                        .font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity)
                    }
                    .tint(state.isPaused ? .green : .yellow)

                    Button(intent: EndRideIntent()) {
                        Label("End", systemImage: "stop.fill")
                            .font(.caption.weight(.semibold))
                            .frame(maxWidth: .infinity)
                    }
                    .tint(.red)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(12)
    }

    // MARK: - Turn Navigation Content (no outer wrapper)

    @ViewBuilder
    private var turnNavigationContent: some View {
        if let dir = state.nextTurnDirection {
            HStack(spacing: 6) {
                Image(systemName: state.nextTurnIcon ?? turnIcon(dir))
                    .font(.body.weight(.bold))
                    .foregroundStyle(.cyan)
                VStack(alignment: .leading, spacing: 1) {
                    HStack(spacing: 4) {
                        Text(dir.capitalized)
                            .font(.subheadline.weight(.semibold))
                        if let dist = state.distanceToNextTurn {
                            Text("in \(formatDistance(dist, imperial: isImperial))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let cue = state.nextTurnCue, !cue.isEmpty {
                        Text(cue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
            }
        } else if state.isOffRoute {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(state.offRouteMessage ?? "Off Route")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.orange)
            }
        }
    }

    // MARK: - Compact Round Controls (used when nav is active)

    private var compactControls: some View {
        HStack(spacing: 6) {
            Button(intent: PauseResumeRideIntent()) {
                Image(systemName: state.isPaused ? "play.fill" : "pause.fill")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .tint(state.isPaused ? .green : .yellow)

            Button(intent: EndRideIntent()) {
                Image(systemName: "stop.fill")
                    .font(.caption2.weight(.semibold))
                    .frame(width: 28, height: 28)
            }
            .tint(.red)
        }
        .buttonStyle(.borderedProminent)
        .buttonBorderShape(.circle)
    }

    // MARK: - Configurable Stats Grid

    @ViewBuilder
    private var statsGrid: some View {
        let topRow = Array(statSlots.prefix(3))
        let bottomRow = Array(statSlots.dropFirst(3).prefix(3))

        VStack(spacing: 0) {
            // Top row
            HStack(spacing: 0) {
                ForEach(Array(topRow.enumerated()), id: \.offset) { i, slot in
                    statCell(for: slot)
                    if i < topRow.count - 1 {
                        Divider().frame(height: 32)
                    }
                }
            }

            if !bottomRow.isEmpty {
                Divider().padding(.horizontal, 16)

                // Bottom row
                HStack(spacing: 0) {
                    ForEach(Array(bottomRow.enumerated()), id: \.offset) { i, slot in
                        statCell(for: slot)
                        if i < bottomRow.count - 1 {
                            Divider().frame(height: 32)
                        }
                    }
                }
            }
        }
    }

    private func statCell(for slotRawValue: String) -> some View {
        let label = metricLabel(slotRawValue)
        let value = resolveMetricValue(slotRawValue)

        return VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
            return formatDistance(v, imperial: isImperial)
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
        if miles < 0.1 {
            let feet = Int(meters * 3.28084)
            return "\(feet) ft"
        }
        return miles < 10
            ? String(format: "%.1f mi", miles)
            : String(format: "%.0f mi", miles)
    } else {
        if meters < 1000 {
            return "\(Int(meters)) m"
        }
        let km = meters / 1000
        return km < 10
            ? String(format: "%.1f km", km)
            : String(format: "%.0f km", km)
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
