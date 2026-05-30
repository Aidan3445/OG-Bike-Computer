//
//  CueEditorTurnPin.swift
//  OG Bike Computer
//
//  Map annotation for a turn while the Cue Editor is open.
//
//  The main pin reflects the turn's CURRENT state (its current direction icon
//  and a color matching the user's decision): green when approved, grey when
//  skipped/dismissed, otherwise the original category color.
//
//  A small badge in the top-right corner only appears once the row has been
//  acted on AND the resulting color differs from the original category color
//  — e.g. Good→Approved stays plain green (no badge), but Missing→Added shows
//  a red badge on a green arrow.
//

import SwiftUI

/// Annotation container — observes the editor view-model directly so the pin
/// refreshes live when state changes, regardless of MapKit's annotation caching.
struct CueEditorTurnPin: View {
    @ObservedObject var editor: CueEditorViewModel
    let entry: CueEntry

    var body: some View {
        let status = editor.status(for: entry)
        let direction = editor.displayDirection(for: entry)
        let isSelected = editor.selection == entry.id
        let anySelected = editor.selection != nil

        CueEditorTurnPinBody(
            entry: entry,
            status: status,
            currentDirection: direction,
            isSelected: isSelected,
            anySelected: anySelected
        )
    }
}

/// Pure presentation — no view-model dependency, just the values needed to draw.
private struct CueEditorTurnPinBody: View {
    let entry: CueEntry
    let status: CueEntryStatus
    let currentDirection: TurnDirection
    let isSelected: Bool
    let anySelected: Bool

    var body: some View {
        let bright = !anySelected || isSelected
        let stroke = isSelected ? Color.white : Color.white.opacity(0.7)
        let baseSize: CGFloat = isSelected ? 22 : 16
        let opacity: Double = bright ? (status == .skipped ? 0.55 : 0.95) : 0.45

        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(currentColor.opacity(opacity))
                    .frame(width: baseSize, height: baseSize)
                    .overlay(
                        Circle().stroke(stroke, lineWidth: isSelected ? 3 : 2)
                    )
                    .shadow(radius: isSelected ? 4 : 1)

                Image(systemName: currentDirection.icon)
                    .font(.system(size: isSelected ? 10 : 8, weight: .bold))
                    .foregroundStyle(.white)
            }

            if shouldShowBadge {
                Circle()
                    .fill(originColor)
                    .frame(width: baseSize * 0.45, height: baseSize * 0.45)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 1.2)
                    )
                    .opacity(bright ? 1.0 : 0.55)
                    .offset(x: baseSize * 0.28, y: -baseSize * 0.28)
            }
        }
        // Leave room for the overhanging badge so taps still land on the pin.
        .frame(width: baseSize * 1.4, height: baseSize * 1.4, alignment: .center)
    }

    /// Show the origin badge only once the row has been acted on AND the
    /// resulting visual differs from the original — i.e. there's something
    /// useful to convey about where it came from. User-added cues never show
    /// a badge: they're authored as-is, there's no "origin" to recall.
    private var shouldShowBadge: Bool {
        guard status != .pending else { return false }
        if entry.kind == .userAdded { return false }
        return currentColor != originColor
    }

    /// Color driven by the current decision. User-added cues stay in their
    /// origin color (blue) regardless of state — they don't transition to
    /// green on approval because they were already "approved" by being added.
    private var currentColor: Color {
        if entry.kind == .userAdded && status != .skipped {
            return originColor
        }
        switch status {
        case .skipped:  return .gray
        case .approved: return .green
        case .pending:  return originColor
        }
    }

    /// Color driven by the entry's original classification.
    private var originColor: Color {
        switch entry.kind {
        case .missingDetected, .missingNameOnly: return .red
        case .extra:                              return .yellow
        case .edit:                               return .orange
        case .userAdded:                          return .blue
        case .good:                               return .green
        }
    }
}
