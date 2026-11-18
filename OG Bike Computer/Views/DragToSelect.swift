//
//  DragToSelect.swift
//  OG Bike Computer
//

import SwiftUI

/// Photos-style selection for a List in Select mode: hold a row, then drag,
/// and every row between it and your finger takes the opposite of the first
/// row's state. Rows outside that span go back to how they were, so dragging
/// back un-does. The list stops scrolling while you drag, and holding near
/// the top or bottom edge scrolls it smoothly, faster the closer you get. A
/// hold without moving is just a tap.
struct DragToSelect: ViewModifier {
    let isEnabled: Bool
    /// Row IDs in the order the list shows them.
    let orderedIDs: [UUID]
    let isSelected: (UUID) -> Bool
    let setSelected: (UUID, Bool) -> Void

    @State private var isDragging = false
    @State private var tracker = DragSelectTracker()

    private static let edgeZone: CGFloat = 70
    /// Points per second at the very edge.
    private static let maxScrollSpeed: CGFloat = 1100

    func body(content: Content) -> some View {
        content
            .environment(\.dragSelectTracker, tracker)
            .onGeometryChange(for: CGRect.self) { proxy in
                let frame = proxy.frame(in: .global)
                let insets = proxy.safeAreaInsets
                return CGRect(
                    x: frame.minX, y: frame.minY + insets.top,
                    width: frame.width, height: max(0, frame.height - insets.top - insets.bottom))
            } action: { [tracker] area in
                tracker.visibleArea = area
            }
            .scrollDisabled(isDragging)
            .simultaneousGesture(dragGesture, including: isEnabled ? .all : .subviews)
            .onChange(of: isEnabled) { _, enabled in
                if !enabled { finish() }
            }
    }

    private var dragGesture: some Gesture {
        LongPressGesture(minimumDuration: 0.3)
            .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .global))
            .onChanged { value in
                guard case .second(true, let drag) = value else { return }
                isDragging = true
                guard let drag else { return }
                // Nothing changes until the finger moves, so a still hold
                // stays a tap.
                guard drag.translation != .zero || tracker.anchorID != nil else { return }
                if tracker.anchorID == nil, let anchor = rowID(at: drag.startLocation) {
                    tracker.anchorID = anchor
                    tracker.target = !isSelected(anchor)
                    tracker.baseline = Set(orderedIDs.filter(isSelected))
                }
                tracker.lastLocation = drag.location
                applySelection(at: drag.location)
                updateAutoScroll()
            }
            .onEnded { _ in finish() }
    }

    private func finish() {
        tracker.stopDisplayLink()
        tracker.onFrame = nil
        tracker.anchorID = nil
        tracker.lastLocation = nil
        isDragging = false
    }

    /// The row under a point, or the nearest one when it's between rows or
    /// past the visible ones.
    private func rowID(at point: CGPoint) -> UUID? {
        let ids = Set(orderedIDs)
        let rows = tracker.rowFrames.filter { ids.contains($0.key) }
        if let hit = rows.first(where: { $0.value.minY <= point.y && point.y <= $0.value.maxY }) {
            return hit.key
        }
        return rows.min { distance($0.value, point.y) < distance($1.value, point.y) }?.key
    }

    private func distance(_ frame: CGRect, _ y: CGFloat) -> CGFloat {
        y < frame.minY ? frame.minY - y : y - frame.maxY
    }

    private func applySelection(at point: CGPoint) {
        guard let anchor = tracker.anchorID,
              let current = rowID(at: point),
              let a = orderedIDs.firstIndex(of: anchor),
              let c = orderedIDs.firstIndex(of: current) else { return }
        let span = min(a, c)...max(a, c)
        let wanted = orderedIDs.enumerated().map { i, id in
            (id, span.contains(i) ? tracker.target : tracker.baseline.contains(id))
        }
        // Deselect first, so a capped selection has room for the new picks.
        for (id, want) in wanted where !want && isSelected(id) { setSelected(id, false) }
        for (id, want) in wanted where want && !isSelected(id) { setSelected(id, true) }
    }

    /// How hard to scroll: negative toward the top, positive toward the
    /// bottom, growing from 0 at the inside of the edge zone to 1 at the edge.
    private func edgePush() -> CGFloat {
        guard let y = tracker.lastLocation?.y else { return 0 }
        let area = tracker.visibleArea
        let topDepth = (area.minY + Self.edgeZone) - y
        let bottomDepth = y - (area.maxY - Self.edgeZone)
        if topDepth > 0 { return -min(topDepth / Self.edgeZone, 1) }
        if bottomDepth > 0 { return min(bottomDepth / Self.edgeZone, 1) }
        return 0
    }

    private func updateAutoScroll() {
        if edgePush() == 0 {
            tracker.stopDisplayLink()
        } else {
            tracker.onFrame = { dt in autoScrollFrame(dt) }
            tracker.startDisplayLink()
        }
    }

    /// Moves the list a little each frame, then re-applies the selection for
    /// wherever the finger now sits over it.
    private func autoScrollFrame(_ dt: CFTimeInterval) {
        let push = edgePush()
        guard push != 0, let scrollView = tracker.scrollView, let location = tracker.lastLocation else {
            tracker.stopDisplayLink()
            return
        }
        let inset = scrollView.adjustedContentInset
        let minY = -inset.top
        let maxY = max(minY, scrollView.contentSize.height - scrollView.bounds.height + inset.bottom)
        var offset = scrollView.contentOffset
        offset.y = min(max(offset.y + push * Self.maxScrollSpeed * dt, minY), maxY)
        guard offset != scrollView.contentOffset else { return }
        scrollView.setContentOffset(offset, animated: false)
        applySelection(at: location)
    }
}

/// Frames and drag bookkeeping change every scroll frame, so they live in a
/// reference that doesn't redraw the list when it changes. Rows write their
/// on-screen frame here (nil once they scroll away) and hand over the list's
/// scroll view, which edge scrolling moves.
final class DragSelectTracker: NSObject {
    var rowFrames: [UUID: CGRect] = [:]
    var visibleArea: CGRect = .zero
    weak var scrollView: UIScrollView?
    var anchorID: UUID?
    var target = true
    var baseline: Set<UUID> = []
    var lastLocation: CGPoint?
    var displayLink: CADisplayLink?
    var onFrame: ((CFTimeInterval) -> Void)?

    func startDisplayLink() {
        guard displayLink == nil else { return }
        let link = CADisplayLink(target: self, selector: #selector(frame(_:)))
        link.add(to: .main, forMode: .common)
        displayLink = link
    }

    func stopDisplayLink() {
        displayLink?.invalidate()
        displayLink = nil
    }

    @objc private func frame(_ link: CADisplayLink) {
        onFrame?(link.targetTimestamp - link.timestamp)
    }
}

extension EnvironmentValues {
    @Entry var dragSelectTracker: DragSelectTracker? = nil
}

/// Finds the list's UIKit scroll view by walking up from inside a row.
private struct ScrollViewFinder: UIViewRepresentable {
    let found: (UIScrollView) -> Void

    func makeUIView(context: Context) -> FinderView {
        let view = FinderView()
        view.found = found
        return view
    }

    func updateUIView(_ view: FinderView, context: Context) {
        view.found = found
    }

    final class FinderView: UIView {
        var found: ((UIScrollView) -> Void)?

        override func didMoveToWindow() {
            super.didMoveToWindow()
            var current = superview
            while let view = current {
                if view is UICollectionView || view is UITableView, let scroll = view as? UIScrollView {
                    found?(scroll)
                    return
                }
                current = view.superview
            }
        }
    }
}

private struct DragSelectRow: ViewModifier {
    let id: UUID
    @Environment(\.dragSelectTracker) private var tracker

    func body(content: Content) -> some View {
        content
            .onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: { tracker?.rowFrames[id] = $0 }
            .onDisappear { tracker?.rowFrames[id] = nil }
            .background(ScrollViewFinder { tracker?.scrollView = $0 }.allowsHitTesting(false))
    }
}

extension View {
    /// Turns on drag-to-select for a List. Rows mark themselves with
    /// `dragSelectRow(_:)`.
    func dragToSelect(
        isEnabled: Bool,
        orderedIDs: [UUID],
        isSelected: @escaping (UUID) -> Bool,
        setSelected: @escaping (UUID, Bool) -> Void
    ) -> some View {
        modifier(DragToSelect(
            isEnabled: isEnabled, orderedIDs: orderedIDs,
            isSelected: isSelected, setSelected: setSelected))
    }

    func dragSelectRow(_ id: UUID) -> some View {
        modifier(DragSelectRow(id: id))
    }
}
