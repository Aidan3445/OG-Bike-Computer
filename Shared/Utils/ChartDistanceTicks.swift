//
//  ChartDistanceTicks.swift
//  OG Bike Computer
//
//  Distance ticks for chart x-axes. Shared by the axis labels and the dashed
//  distance rules so the two always land on the same values.
//

import SwiftUI

/// Nice-interval ticks across `range` (in display units), about `desiredCount`
/// of them.
func chartDistanceTicks(in range: ClosedRange<Double>, desiredCount: Int = 5) -> [Double] {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return [range.lowerBound] }

    let magnitude = pow(10, floor(log10(span / Double(desiredCount))))
    var candidates: [Double] = []
    for scale in [magnitude / 10, magnitude, magnitude * 10] {
        // 2.5 steps below 1 would need two decimals in the labels.
        let mantissas: [Double] = scale >= 1 ? [1, 2, 2.5, 5] : [1, 2, 5]
        candidates += mantissas.map { $0 * scale }
    }

    func ticks(step: Double) -> [Double] {
        // Small slack so float error doesn't drop a tick that lands on the end.
        let end = range.upperBound + step * 1e-6
        var values: [Double] = []
        var i = (range.lowerBound / step).rounded(.up)
        while i * step <= end {
            values.append(i * step)
            i += 1
        }
        return values
    }

    // Reversed so a tie goes to the wider step and fewer labels.
    let best = candidates.reversed().min { a, b in
        abs(ticks(step: a).count - desiredCount) < abs(ticks(step: b).count - desiredCount)
    } ?? span
    return ticks(step: best)
}

/// Pair with `AxisMarks(preset: .aligned)`, which centers labels under their
/// tick. Near the right edge the label flips to trailing so it stays inside
/// the chart. Charts rejects a plain `.top` here, so nil means default.
func chartDistanceLabelAnchor(for value: Double, in range: ClosedRange<Double>) -> UnitPoint? {
    let span = range.upperBound - range.lowerBound
    guard span > 0 else { return nil }
    return (range.upperBound - value) / span < 0.08 ? .topTrailing : nil
}

/// For a leading y-axis. A label on the top gridline hangs below it instead
/// of centering on it, so the top half isn't cut off.
func chartYLabelAnchor(for value: Double, in domain: ClosedRange<Double>) -> UnitPoint? {
    let span = domain.upperBound - domain.lowerBound
    guard span > 0 else { return nil }
    return (domain.upperBound - value) / span < 0.05 ? .topTrailing : nil
}

/// Whole numbers drop the decimal, sub-unit steps keep one.
func chartDistanceLabel(_ value: Double) -> String {
    let rounded = value.rounded()
    return abs(value - rounded) < 0.001 ? "\(Int(rounded))" : String(format: "%.1f", value)
}
