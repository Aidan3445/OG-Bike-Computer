//
//  CueEditorPanel.swift
//  OG Bike Computer
//
//  The bottom editor card that replaces the stats panel while the user is in
//  Cue Editor mode. Resizable between roughly 1/4 and 1/2 of the parent height
//  (default ~1/3). Hosts the section/flat toggle, the scrollable list of cue
//  entries, and the per-row action UI (Add / Edit / Skip / Approve).
//

import SwiftUI

struct CueEditorPanel: View {
    @ObservedObject var viewModel: CueEditorViewModel
    /// Parent's available height — used to clamp drag-resize within bounds.
    let availableHeight: CGFloat

    /// Current panel height. Initialized in onAppear to availableHeight/3.
    @State private var height: CGFloat = 0
    @State private var dragStartHeight: CGFloat? = nil

    private var minHeight: CGFloat { availableHeight * 0.25 }
    private var maxHeight: CGFloat { availableHeight * 0.5 }
    private var defaultHeight: CGFloat { availableHeight / 3 }

    var body: some View {
        VStack(spacing: 0) {
            dragHandle
            headerBar
            Divider().opacity(0.35)

            if viewModel.allEntries.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .frame(height: max(minHeight, min(maxHeight, height == 0 ? defaultHeight : height)))
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(.ultraThinMaterial)
                .shadow(radius: 12, y: 4)
        )
        .padding(.horizontal, 12)
        .padding(.bottom, 12)
        .onAppear { if height == 0 { height = defaultHeight } }
    }

    // MARK: - Header

    private var dragHandle: some View {
        Capsule()
            .fill(.secondary)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
            .frame(height: 18)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 4)
                    .onChanged { value in
                        if dragStartHeight == nil { dragStartHeight = height }
                        let proposed = (dragStartHeight ?? height) - value.translation.height
                        height = max(minHeight, min(maxHeight, proposed))
                    }
                    .onEnded { _ in dragStartHeight = nil }
            )
    }

    private var headerBar: some View {
        HStack(spacing: 10) {
            Text("\(resolvedCount) / \(viewModel.allEntries.count) reviewed")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)

            Spacer()

            HStack(spacing: 0) {
                modeButton(.sectioned, systemImage: "list.bullet.indent")
                modeButton(.flat, systemImage: "list.bullet")
            }
            .background(
                Capsule().fill(Color.secondary.opacity(0.18))
            )
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 6)
    }

    private func modeButton(_ mode: CueEditorListMode, systemImage: String) -> some View {
        let isSelected = viewModel.listMode == mode
        return Button {
            guard viewModel.listMode != mode else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                viewModel.listMode = mode
            }
        } label: {
            Image(systemName: systemImage)
                .font(.subheadline.weight(.semibold))
                .frame(width: 44, height: 28)
                .background(
                    Capsule().fill(isSelected ? Color.accentColor.opacity(0.35) : Color.clear)
                )
                .foregroundStyle(isSelected ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
        .contentShape(Capsule())
    }

    private var resolvedCount: Int {
        viewModel.allEntries.reduce(0) { $0 + (viewModel.isResolved($1) ? 1 : 0) }
    }

    // MARK: - List

    @ViewBuilder
    private var listContent: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 6) {
                    switch viewModel.listMode {
                    case .sectioned:
                        section(kind: .missingDetected, title: "Missing", color: .red,
                                entries: viewModel.classification.missing)
                        section(kind: .extra, title: "Extra", color: .yellow,
                                entries: viewModel.classification.extra)
                        section(kind: .edit, title: "Edit", color: .orange,
                                entries: viewModel.classification.edit)
                        section(kind: .good, title: "Good", color: .green,
                                entries: viewModel.classification.good)
                    case .flat:
                        ForEach(viewModel.allEntries) { entry in
                            rowView(entry)
                                .id(entry.id)
                        }
                    }
                }
                .padding(.horizontal, 12)
                .padding(.top, 6)
                .padding(.bottom, 14)
            }
            .onChange(of: viewModel.selection) { _, newID in
                scrollSelectionIntoView(proxy: proxy, id: newID)
            }
            .onChange(of: viewModel.listMode) { _, _ in
                // Layout just changed — bring the selected row back into view.
                scrollSelectionIntoView(proxy: proxy, id: viewModel.selection)
            }
        }
    }

    /// Sectioned mode lumps missingDetected + missingNameOnly under the same
    /// header (keyed by .missingDetected); map the row's kind to that header.
    private func sectionKey(for kind: CueEntryKind) -> CueEntryKind {
        switch kind {
        case .missingNameOnly: return .missingDetected
        default: return kind
        }
    }

    /// Scroll the currently-selected row back into view. Expands its section
    /// first if needed (sectioned mode), and waits a tick so layout settles
    /// after a mode flip or section toggle.
    private func scrollSelectionIntoView(proxy: ScrollViewProxy, id: CueEntryID?) {
        guard let id = id else { return }
        if viewModel.listMode == .sectioned,
           let entry = viewModel.allEntries.first(where: { $0.id == id }) {
            let key = sectionKey(for: entry.kind)
            if viewModel.isCollapsed(key) {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleSection(key)
                }
            }
        }
        // Defer one runloop turn so the new layout has rows to scroll to.
        DispatchQueue.main.async {
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "checkmark.seal")
                .font(.title)
                .foregroundStyle(.secondary)
            Text("No turns on this route.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Sections

    @ViewBuilder
    private func section(kind: CueEntryKind, title: String, color: Color, entries: [CueEntry]) -> some View {
        // For Missing we lump missingDetected + missingNameOnly together; both
        // rows use the same section. The header tag is "missingDetected" but
        // controls collapse for the merged group.
        if entries.isEmpty { EmptyView() } else {
            let reviewed = entries.filter { viewModel.isResolved($0) }.count
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    viewModel.toggleSection(kind)
                }
            } label: {
                HStack(spacing: 8) {
                    Circle().fill(color).frame(width: 10, height: 10)
                    Text(title).font(.subheadline.weight(.semibold))
                    Text("\(reviewed) / \(entries.count) reviewed")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: viewModel.isCollapsed(kind) ? "chevron.right" : "chevron.down")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 4)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if !viewModel.isCollapsed(kind) {
                ForEach(entries) { entry in
                    rowView(entry)
                        .id(entry.id)
                }
            }
        }
    }

    // MARK: - Row

    private func rowView(_ entry: CueEntry) -> some View {
        let selected = viewModel.selection == entry.id
        let status = viewModel.status(for: entry)
        let dir = viewModel.displayDirection(for: entry)
        let name = viewModel.displayName(for: entry)

        return VStack(alignment: .leading, spacing: 6) {
            Button {
                if selected {
                    viewModel.select(nil)
                } else {
                    viewModel.select(entry.id)
                }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: dir.icon)
                        .font(.system(size: 16, weight: .semibold))
                        .frame(width: 24)
                        .foregroundStyle(badgeColor(entry: entry, status: status))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(name?.isEmpty == false ? name! : "—")
                            .font(.subheadline.weight(.medium))
                            .foregroundStyle(status == .skipped ? Color.secondary : Color.primary)
                            .lineLimit(1)
                        HStack(spacing: 6) {
                            Text(dir.label)
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                            Text("·").font(.caption2).foregroundStyle(.secondary)
                            Text(formatDistance(entry.turn.distanceFromStart))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                    Spacer()
                    statusBadge(entry: entry, status: status)
                }
                .padding(.vertical, 8)
                .padding(.horizontal, 10)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(selected ? Color.accentColor.opacity(0.15) : Color.secondary.opacity(0.08))
                )
            }
            .buttonStyle(.plain)

            if selected {
                actionStrip(entry: entry, status: status)
                    .transition(.opacity)
            }
        }
        .opacity(status == .skipped ? 0.6 : 1.0)
    }

    private func badgeColor(entry: CueEntry, status: CueEntryStatus) -> Color {
        if status == .skipped { return .gray }
        switch entry.kind {
        case .missingDetected, .missingNameOnly: return .red
        case .extra:                              return .yellow
        case .edit:                               return .orange
        case .good:                               return .green
        }
    }

    @ViewBuilder
    private func statusBadge(entry: CueEntry, status: CueEntryStatus) -> some View {
        switch status {
        case .pending:
            EmptyView()
        case .approved:
            Label {
                Text(entry.kind == .missingDetected && viewModel.isCustomized(entry) ? "Added" : "OK")
                    .font(.caption2.weight(.semibold))
            } icon: {
                Image(systemName: "checkmark.circle.fill")
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.green)
        case .skipped:
            Label {
                Text("Skipped").font(.caption2.weight(.semibold))
            } icon: {
                Image(systemName: "minus.circle.fill")
            }
            .labelStyle(.titleAndIcon)
            .foregroundStyle(.gray)
        }
    }

    // MARK: - Per-row actions

    @ViewBuilder
    private func actionStrip(entry: CueEntry, status: CueEntryStatus) -> some View {
        if viewModel.isComposingAdd, case .detected = entry.id {
            composeForm(entry: entry, mode: .add)
        } else if viewModel.isComposingEdit, case .waypoint = entry.id {
            composeForm(entry: entry, mode: .edit)
        } else {
            HStack(spacing: 8) {
                switch entry.kind {
                case .missingDetected:
                    Button { viewModel.beginAdd(entry) } label: {
                        Label("Add", systemImage: "plus.circle")
                    }
                    Button { viewModel.dismissMissing(entry) } label: {
                        Label("Skip", systemImage: "minus.circle")
                    }
                case .missingNameOnly, .extra, .edit, .good:
                    Button { viewModel.beginEditWaypoint(entry) } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    Button { viewModel.skipWaypoint(entry) } label: {
                        Label("Skip", systemImage: "minus.circle")
                    }
                    Button { viewModel.approveWaypoint(entry) } label: {
                        Label("OK", systemImage: "checkmark.circle")
                    }
                }
                Spacer()
                if viewModel.isCustomized(entry) {
                    Button {
                        viewModel.resetEditsToOriginal(entry)
                    } label: {
                        Image(systemName: "arrow.uturn.backward")
                    }
                    .help("Reset to original")
                }
            }
            .font(.footnote.weight(.medium))
            .buttonStyle(.bordered)
            .controlSize(.small)
            .padding(.horizontal, 6)
            .padding(.bottom, 4)
        }
    }

    private enum ComposeMode { case add, edit }

    @ViewBuilder
    private func composeForm(entry: CueEntry, mode: ComposeMode) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            DirectionPicker(selection: $viewModel.draft.direction)
            TextField("Street / road name", text: $viewModel.draft.streetName)
                .textFieldStyle(.roundedBorder)
                .autocorrectionDisabled()

            advancedFullCue(entry: entry)

            HStack(spacing: 8) {
                Button {
                    switch mode {
                    case .add:  viewModel.cancelAdd()
                    case .edit: viewModel.cancelEdit()
                    }
                } label: { Text("Cancel") }

                if mode == .add {
                    Button { viewModel.clearDraft() } label: {
                        Label("Clear", systemImage: "xmark.circle")
                    }
                }

                Spacer()

                Button {
                    switch mode {
                    case .add:  viewModel.saveAdd(entry)
                    case .edit: viewModel.saveEditWaypoint(entry)
                    }
                } label: {
                    Label(mode == .add ? "Add" : "Save", systemImage: "checkmark.circle.fill")
                }
                .buttonStyle(.borderedProminent)
            }
            .controlSize(.small)
            .font(.footnote.weight(.medium))
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.secondary.opacity(0.08))
        )
    }

    /// Disclosure-wrapped "Custom cue text" field. Hidden by default; expands
    /// to a TextField whose placeholder shows the current resolved cue (e.g.
    /// the auto-composed "Turn left onto Main Street" or the original
    /// description). Used for roundabout-style phrasings the template won't
    /// produce naturally.
    @ViewBuilder
    private func advancedFullCue(entry: CueEntry) -> some View {
        DisclosureGroup {
            TextField(
                viewModel.displayFullCue(for: entry) ?? "Custom cue text",
                text: $viewModel.draft.fullCueText,
                axis: .vertical
            )
            .lineLimit(1...3)
            .textFieldStyle(.roundedBorder)
            .autocorrectionDisabled()
            .padding(.top, 4)
        } label: {
            Text("Custom cue text")
                .font(.caption.weight(.medium))
                .foregroundStyle(.secondary)
        }
    }
}

/// Flat direction selector — all 8 options always visible, laid out in two
/// rows by side (lefts above, rights below). The slight/sharp variants use
/// short labels ("Slight" / "Sharp") since their icon already conveys the
/// direction; full labels were getting truncated.
private struct DirectionPicker: View {
    @Binding var selection: TurnDirection

    private let topRow: [TurnDirection] = [.left, .slightLeft, .sharpLeft, .straight]
    private let bottomRow: [TurnDirection] = [.right, .slightRight, .sharpRight, .uTurn]

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                ForEach(topRow, id: \.self) { chip($0) }
            }
            HStack(spacing: 4) {
                ForEach(bottomRow, id: \.self) { chip($0) }
            }
        }
    }

    /// Compact label used in the picker chip — keeps the full TurnDirection
    /// label for primary directions but drops the side suffix from the
    /// modifier variants so the chips don't overflow.
    private func shortLabel(_ option: TurnDirection) -> String {
        switch option {
        case .slightLeft, .slightRight: return "Slight"
        case .sharpLeft, .sharpRight:   return "Sharp"
        default:                         return option.label
        }
    }

    private func chip(_ option: TurnDirection) -> some View {
        let isSelected = selection == option
        return Button {
            selection = option
        } label: {
            HStack(spacing: 4) {
                Image(systemName: option.icon)
                Text(shortLabel(option))
                    .font(.caption2.weight(.medium))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule().fill(isSelected ? Color.accentColor.opacity(0.25) : Color.secondary.opacity(0.12))
            )
            .overlay(
                Capsule().stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }
}
