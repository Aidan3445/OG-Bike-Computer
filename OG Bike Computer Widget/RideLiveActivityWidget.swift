//
//  RideLiveActivityWidget.swift
//  OG Bike Computer Widget
//
//  Created by Aidan Weinberg on 3/28/26.
//

#if canImport(ActivityKit)
import ActivityKit
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
                .activityBackgroundTint(.black)
                .activitySystemActionForegroundColor(.white)
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
                        Text(formatDuration(context.state.movingTime))
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
        }
    }
}

// MARK: - Lock Screen View

private struct LockScreenView: View {
    let context: ActivityViewContext<RideActivityAttributes>

    private var state: RideActivityAttributes.ContentState { context.state }
    private var isImperial: Bool { context.attributes.isImperial }

    var body: some View {
        VStack(spacing: 8) {
            // Turn alert bar (only with route)
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
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        if let cue = state.nextTurnCue, !cue.isEmpty {
                            Text(cue)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.cyan.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            } else if state.isOffRoute {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                    Text(state.offRouteMessage ?? "Off Route")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.orange)
                    Spacer()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(.orange.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            }

            // Stats grid
            HStack(spacing: 0) {
                statCell(
                    label: "Distance",
                    value: formatDistance(state.totalDistance, imperial: isImperial)
                )
                Divider().frame(height: 32)
                statCell(
                    label: "Moving",
                    value: formatDuration(state.movingTime)
                )
                Divider().frame(height: 32)
                statCell(
                    label: "Avg Speed",
                    value: formatSpeed(state.averageSpeed, imperial: isImperial)
                )
            }

            // Route remaining (if navigating)
            if let remaining = state.routeDistanceRemaining {
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
        }
        .padding(12)
    }

    private func statCell(label: String, value: String) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(.subheadline.weight(.semibold))
                .monospacedDigit()
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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

private func formatDuration(_ seconds: TimeInterval) -> String {
    let h = Int(seconds) / 3600
    let m = (Int(seconds) % 3600) / 60
    let s = Int(seconds) % 60
    if h > 0 {
        return String(format: "%d:%02d:%02d", h, m, s)
    }
    return String(format: "%d:%02d", m, s)
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
