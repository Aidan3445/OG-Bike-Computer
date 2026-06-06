//
//  RideHistoryView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI

struct RideHistoryView: View {
    @ObservedObject var rideStore: RideStore
    @ObservedObject var routeStore: RouteStore
    @ObservedObject private var connectivity = ConnectivityManager.shared

    static let maxSelection = 32

    @State private var isSelectionMode = false
    /// Ordered list of selected ride IDs — position in the array = displayed number.
    @State private var selectedIDs: [UUID] = []
    @State private var showDeleteConfirm = false
    @State private var navigateToMulti = false

    private var heldRides: [RideSummary] {
        guard connectivity.isReachable else { return [] }
        return rideStore.rides.filter { $0.onHold }
    }

    private var completedRides: [RideSummary] {
        rideStore.rides.filter { !$0.onHold }
    }

    private var sections: [(DateSection, [RideSummary])] {
        DateSection.group(completedRides, by: \.date)
    }

    /// Show the generic "waiting for ride from watch" placeholder only when we're
    /// expecting a ride but no summary has arrived yet (no row to update in place).
    /// Held rides count as "arrived" — if one is already showing, the placeholder
    /// is redundant and should be hidden even if the awaiting flag is still set.
    private var showAwaitingPlaceholder: Bool {
        connectivity.isAwaitingIncomingRide &&
            connectivity.pendingTransferRideIDs.isEmpty &&
            heldRides.isEmpty
    }

    private var selectedRides: [RideSummary] {
        // Honor user-selection order, not list order.
        selectedIDs.compactMap { id in completedRides.first(where: { $0.id == id }) }
    }

    var body: some View {
        Group {
            if rideStore.rides.isEmpty && !showAwaitingPlaceholder {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "bicycle",
                    description: Text("Completed rides from your watch will appear here."))
            } else {
                List {
                    if showAwaitingPlaceholder {
                        Section {
                            AwaitingRideRow()
                        }
                    }

                    if !heldRides.isEmpty {
                        Section {
                            ForEach(heldRides) { ride in
                                NavigationLink {
                                    RideDetailView(ride: ride, rideStore: rideStore)
                                } label: {
                                    HeldRideRow(ride: ride)
                                }
                                .disabled(isSelectionMode)
                            }
                        } header: {
                            Text("On Hold")
                                .foregroundStyle(.orange)
                        }
                    }

                    ForEach(sections, id: \.0) { section, rides in
                        Section {
                            ForEach(rides) { ride in
                                rideListRow(ride: ride)
                            }
                            .onDelete { indices in
                                guard !isSelectionMode else { return }
                                for i in indices {
                                    rideStore.delete(rides[i])
                                }
                            }
                        } header: {
                            Text(section.title)
                        }
                    }
                }
            }
        }
        .navigationTitle(isSelectionMode ? "\(selectedIDs.count)/\(Self.maxSelection) Selected" : "Rides")
        .navigationBarTitleDisplayMode(isSelectionMode ? .inline : .automatic)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                if !isSelectionMode {
                    ConnectionStatusButton(connectivity: connectivity, routeStore: routeStore)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                if completedRides.isEmpty {
                    EmptyView()
                } else if isSelectionMode {
                    Button("Cancel") {
                        exitSelectionMode()
                    }
                } else {
                    Button {
                        withAnimation { isSelectionMode = true }
                    } label: {
                        Text("Select")
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if isSelectionMode {
                selectionActionBar()
            }
        }
        .navigationDestination(isPresented: $navigateToMulti) {
            MultiRideDetailView(rides: selectedRides, rideStore: rideStore)
        }
        .confirmationDialog(
            "Delete \(selectedIDs.count) \(selectedIDs.count == 1 ? "ride" : "rides")?",
            isPresented: $showDeleteConfirm,
            titleVisibility: .visible
        ) {
            Button("Delete", role: .destructive) {
                let toDelete = selectedRides
                for ride in toDelete { rideStore.delete(ride) }
                exitSelectionMode()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This cannot be undone.")
        }
    }

    @ViewBuilder
    private func rideListRow(ride: RideSummary) -> some View {
        let isTransferring = connectivity.pendingTransferRideIDs.contains(ride.id)
        let selectionIndex = selectedIDs.firstIndex(of: ride.id).map { $0 + 1 }

        if isSelectionMode {
            HStack(spacing: 12) {
                SelectionIndicator(index: selectionIndex)
                RideRow(
                    ride: ride,
                    onRename: { newName in rideStore.rename(ride, to: newName) },
                    isTransferring: isTransferring
                )
            }
            .contentShape(Rectangle())
            .onTapGesture { toggleSelection(ride) }
            // Disable swipe-actions while selecting so they don't interfere with taps.
            .deleteDisabled(true)
        } else if isTransferring {
            RideRow(
                ride: ride,
                onRename: { newName in rideStore.rename(ride, to: newName) },
                isTransferring: true
            )
        } else {
            NavigationLink {
                RideDetailView(ride: ride, rideStore: rideStore)
            } label: {
                RideRow(
                    ride: ride,
                    onRename: { newName in rideStore.rename(ride, to: newName) },
                    isTransferring: false
                )
            }
        }
    }

    @ViewBuilder
    private func selectionActionBar() -> some View {
        HStack(spacing: 12) {
            Button {
                navigateToMulti = true
            } label: {
                Label("View", systemImage: "arrow.triangle.merge")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(selectedIDs.isEmpty)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
            .disabled(selectedIDs.isEmpty)
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.regularMaterial)
    }

    private func toggleSelection(_ ride: RideSummary) {
        if let idx = selectedIDs.firstIndex(of: ride.id) {
            selectedIDs.remove(at: idx)
        } else {
            guard selectedIDs.count < Self.maxSelection else { return }
            selectedIDs.append(ride.id)
        }
    }

    private func exitSelectionMode() {
        withAnimation {
            isSelectionMode = false
            selectedIDs.removeAll()
        }
    }
}

/// Ordered numbered-circle indicator. Empty circle when `index == nil`,
/// filled accent circle with the 1-based position when selected.
struct SelectionIndicator: View {
    let index: Int?

    var body: some View {
        ZStack {
            if let i = index {
                Circle()
                    .fill(Color.accentColor)
                    .frame(width: 24, height: 24)
                Text("\(i)")
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                    .monospacedDigit()
            } else {
                Circle()
                    .stroke(Color.secondary, lineWidth: 1.5)
                    .frame(width: 24, height: 24)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: index)
    }
}
