//
//  MapStatsPanel.swift
//  OG Bike Computer
//

import SwiftUI

/// Bottom stats panel shared by ride, route and multi-ride detail. Collapses
/// to a round button and pages through the screen's pages. Its height follows
/// whichever page is showing, so short pages leave no dead space and tall
/// ones aren't clipped (past a cap they scroll).
///
/// Expansion belongs to a page: swiping to the chart shrinks the panel to the
/// chart, and swiping back restores the stats page as it was.
struct MapStatsPanel<Pages: View>: View {
    @Binding var isOpen: Bool
    @Binding var page: Int
    /// Pages currently showing everything. Only pages in `expandablePages` go in.
    @Binding var expandedPages: Set<Int>
    let pageCount: Int
    var expandablePages: Set<Int> = []
    /// Shown above the pages, wrapping rather than truncating.
    var title: String? = nil
    /// Each page should end in `.statsPanelPage(index)`.
    @ViewBuilder let pages: () -> Pages

    @State private var heights = StatsPanelHeights()
    /// What the pager is actually sized to. Measurements arrive after the
    /// change that caused them, outside any animation, so this follows
    /// `pageHeight` inside its own animation. That way the background and
    /// the content resize together instead of the box snapping.
    @State private var displayedHeight: CGFloat?

    private static var maxPageHeight: CGFloat { 360 }
    private static var spring: Animation { .spring(response: 0.35, dampingFraction: 0.85) }

    private var isExpandable: Bool { expandablePages.contains(page) }
    private var isExpanded: Bool { expandedPages.contains(page) }
    private var pageHeight: CGFloat { min(heights.byPage[page] ?? 120, Self.maxPageHeight) }

    var body: some View {
        VStack(spacing: 6) {
            if isOpen {
                dragHandle

                if let title {
                    Text(title)
                        .font(.headline)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity)
                        .padding(.horizontal)
                }

                TabView(selection: $page) {
                    pages()
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(height: displayedHeight ?? pageHeight)
                .environment(\.statsPanelHeights, heights)

                if isExpandable {
                    moreLessButton
                }

                if pageCount > 1 {
                    pageDots
                }
            } else {
                Image(systemName: "chart.bar.xaxis")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.primary)
                    .padding(.top, 8)
            }
        }
        .padding(.horizontal, isOpen ? 16 : 0)
        .padding(.bottom, 8)
        .frame(maxWidth: isOpen ? .infinity : nil, alignment: isOpen ? .center : .trailing)
        .frame(width: isOpen ? nil : 48, height: isOpen ? nil : 48)
        .background(
            RoundedRectangle(cornerRadius: isOpen ? 16 : 24)
                .fill(.ultraThinMaterial)
                .shadow(radius: 12, y: 4)
        )
        .padding(.horizontal, isOpen ? 12 : 0)
        .padding(.bottom, isOpen ? 12 : 24)
        .padding(.trailing, isOpen ? 0 : 16)
        .frame(maxWidth: .infinity, alignment: isOpen ? .center : .trailing)
        .contentShape(Rectangle())
        .onTapGesture {
            if !isOpen {
                withAnimation(Self.spring) { isOpen = true }
            }
        }
        .onChange(of: pageHeight) { _, newHeight in
            guard displayedHeight != nil else {
                displayedHeight = newHeight
                return
            }
            withAnimation(Self.spring) { displayedHeight = newHeight }
        }
    }

    /// Tap closes. Drag up expands the page if it can, drag down
    /// un-expands first and closes after that.
    private var dragHandle: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 30)
            .contentShape(Rectangle())
            .onTapGesture {
                withAnimation(Self.spring) { isOpen = false }
            }
            .gesture(
                DragGesture(minimumDistance: 10)
                    .onEnded { value in
                        guard abs(value.translation.height) > 10 else { return }
                        withAnimation(Self.spring) {
                            if value.translation.height < 0 {
                                if isExpandable { expandedPages.insert(page) }
                            } else if isExpanded {
                                expandedPages.remove(page)
                            } else {
                                isOpen = false
                            }
                        }
                    }
            )
    }

    private var moreLessButton: some View {
        Button {
            withAnimation(Self.spring) {
                if isExpanded {
                    expandedPages.remove(page)
                } else {
                    expandedPages.insert(page)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text(isExpanded ? "Less" : "More")
                    .font(.caption2.weight(.medium))
                Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                    .font(.caption2)
            }
            .foregroundStyle(.secondary)
        }
        .buttonStyle(.plain)
    }

    private var pageDots: some View {
        HStack(spacing: 6) {
            ForEach(0..<pageCount, id: \.self) { i in
                Circle()
                    .fill(page == i ? Color.primary : Color.secondary.opacity(0.4))
                    .frame(width: 6, height: 6)
            }
        }
    }
}

/// Each page's content height, written by the pages themselves. It goes
/// through the environment because environment values reach into the pager's
/// pages, where preferences don't come back out.
@Observable final class StatsPanelHeights {
    var byPage: [Int: CGFloat] = [:]

    func report(_ height: CGFloat, page: Int) {
        if byPage[page] != height { byPage[page] = height }
    }
}

extension EnvironmentValues {
    @Entry var statsPanelHeights: StatsPanelHeights? = nil
}

private struct StatsPanelPage: ViewModifier {
    let index: Int
    @Environment(\.statsPanelHeights) private var heights

    func body(content: Content) -> some View {
        // The scroll view gives the content its natural height to measure,
        // and lets it scroll once the panel hits its cap.
        ScrollView {
            content
                .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { heights?.report($0, page: index) }
        }
        .scrollBounceBehavior(.basedOnSize)
        .tag(index)
    }
}

extension View {
    /// Marks a page of a `MapStatsPanel`. Don't end the page in a Spacer: the
    /// panel sizes itself to the page's content.
    func statsPanelPage(_ index: Int) -> some View {
        modifier(StatsPanelPage(index: index))
    }
}

#Preview("Stats panel") {
    @Previewable @State var isOpen = true
    @Previewable @State var page = 0
    @Previewable @State var expanded: Set<Int> = []
    ZStack(alignment: .bottom) {
        Color.gray.opacity(0.3).ignoresSafeArea()
        MapStatsPanel(
            isOpen: $isOpen, page: $page, expandedPages: $expanded,
            pageCount: 2, expandablePages: [0], title: "Lakefront Loop to the North Shore and Back"
        ) {
            VStack(spacing: 8) {
                ForEach(0..<(expanded.contains(0) ? 5 : 2), id: \.self) { row in
                    if row > 0 { Divider() }
                    HStack {
                        ForEach(0..<3, id: \.self) { col in
                            Text("Stat \(row * 3 + col + 1)").frame(maxWidth: .infinity)
                        }
                    }
                }
            }
            .statsPanelPage(0)

            Color.green.opacity(0.3)
                .frame(height: 180)
                .overlay(Text("Chart"))
                .statsPanelPage(1)
        }
    }
}
