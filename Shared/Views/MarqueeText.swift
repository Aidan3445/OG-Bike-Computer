//
//  MarqueeText.swift
//  OG Bike Computer
//
//  A horizontally-scrolling text view that carousels its content when the
//  text doesn't fit the available width. When it fits, it renders as a plain
//  Text so there's zero visual change for short cues.
//
//  Layout-wise this view behaves exactly like `Text(...).lineLimit(1)` —
//  it accepts the parent's proposed width, doesn't claim extra space, and
//  doesn't push siblings around. The scrolling animation is drawn purely as
//  an overlay on top of an invisible (opacity-0) base Text that owns the
//  layout.
//
//  Works in both the iOS app and the Live Activity widget (it uses a
//  `TimelineView(.periodic)` driven off Date so the scroll position is a pure
//  function of time — no @State needed). Widget renderers tick this at
//  whatever rate the system allows; on the iPhone foreground it'll be smooth.
//

import SwiftUI

struct MarqueeText: View {
    let text: String
    var font: Font = .body
    var pixelsPerSecond: Double = 30
    /// Pause (seconds) at each end of the scroll so the rider can read the
    /// start and finish before the text moves.
    var endHold: Double = 1.2

    /// The text's natural (unconstrained) width, measured by a hidden probe
    /// placed in `.background`. Background views don't affect parent layout,
    /// so the probe can render at its full natural size without pushing
    /// siblings around.
    @State private var textWidth: CGFloat = 0

    var body: some View {
        // The base Text owns the row's layout: with `.lineLimit(1)` it
        // negotiates width exactly the way a regular Text would (taking
        // natural width when room is plentiful, compressing when not). We
        // hide it with opacity(0) so only the overlay marquee is visible.
        Text(text)
            .font(font)
            .lineLimit(1)
            .opacity(0)
            .overlay(alignment: .leading) {
                GeometryReader { geo in
                    let needsScroll = textWidth > geo.size.width + 0.5
                    if needsScroll {
                        TimelineView(.periodic(from: .now, by: 0.04)) { context in
                            scrollingContent(at: context.date, containerWidth: geo.size.width)
                        }
                        .mask(
                            LinearGradient(
                                stops: [
                                    .init(color: .clear, location: 0.0),
                                    .init(color: .black, location: 0.04),
                                    .init(color: .black, location: 0.92),
                                    .init(color: .clear, location: 1.0)
                                ],
                                startPoint: .leading,
                                endPoint: .trailing
                            )
                        )
                    } else {
                        Text(text)
                            .font(font)
                            .lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .background(
                // Hidden sizing probe. Background doesn't influence the
                // parent's measured size, so we can render the text at its
                // full natural width here without affecting the row layout.
                Text(text)
                    .font(font)
                    .lineLimit(1)
                    .fixedSize()
                    .hidden()
                    .background(
                        GeometryReader { probe in
                            Color.clear.preference(
                                key: TextWidthKey.self,
                                value: probe.size.width
                            )
                        }
                    )
            )
            .onPreferenceChange(TextWidthKey.self) { width in
                // Skip no-op publishes — the probe re-fires on every layout
                // pass (which TimelineView triggers at 25 Hz) even when the
                // measured width is unchanged.
                if abs(width - textWidth) > 0.5 { textWidth = width }
            }
    }

    /// Compute an offset that ping-pongs between left-aligned (0) and
    /// right-justified (-(textWidth - containerWidth)), holding briefly at
    /// each end so the rider can read both edges.
    private func scrollingContent(at date: Date, containerWidth: CGFloat) -> some View {
        let travel = max(0, textWidth - containerWidth)
        let scrollDuration = travel / pixelsPerSecond
        let cycle = endHold + scrollDuration + endHold + scrollDuration
        let phase = date.timeIntervalSinceReferenceDate
            .truncatingRemainder(dividingBy: max(cycle, 0.001))

        let progress: CGFloat
        switch phase {
        case ..<endHold:
            progress = 0                                    // hold at start
        case ..<(endHold + scrollDuration):
            progress = CGFloat((phase - endHold) / scrollDuration)
        case ..<(endHold + scrollDuration + endHold):
            progress = 1                                    // hold at end
        default:
            progress = 1 - CGFloat((phase - endHold - scrollDuration - endHold) / scrollDuration)
        }

        return Text(text)
            .font(font)
            .lineLimit(1)
            .fixedSize()
            .offset(x: -travel * progress)
            .frame(width: containerWidth, alignment: .leading)
            .clipped()
    }
}

private struct TextWidthKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) {
        value = max(value, nextValue())
    }
}
