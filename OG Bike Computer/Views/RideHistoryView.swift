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
    @State private var isExportingZip = false
    @State private var exportZipURL: URL?
    @State private var showExportShareSheet = false
    @State private var hasStravaAuth = false
    @State private var isUploadingMerged = false
    @State private var mergedUploadError: String?
    @State private var mergedUploadWebURL: String?

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
        .sheet(isPresented: $showExportShareSheet) {
            if let url = exportZipURL {
                ShareSheet(activityItems: [url])
            }
        }
        .overlay {
            if isExportingZip || isUploadingMerged {
                ZStack {
                    Color.black.opacity(0.25).ignoresSafeArea()
                    VStack(spacing: 12) {
                        ProgressView()
                        Text(isUploadingMerged
                             ? "Uploading \(selectedIDs.count) \(selectedIDs.count == 1 ? "ride" : "rides") to Strava…"
                             : "Zipping \(selectedIDs.count) \(selectedIDs.count == 1 ? "ride" : "rides")…")
                            .font(.footnote)
                    }
                    .padding(20)
                    .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
                }
                .transition(.opacity)
            }
        }
        .alert("Upload Error", isPresented: .init(
            get: { mergedUploadError != nil },
            set: { if !$0 { mergedUploadError = nil } }
        )) {
            Button("OK") { mergedUploadError = nil }
        } message: {
            Text(mergedUploadError ?? "")
        }
        .alert("Uploaded to Strava", isPresented: .init(
            get: { mergedUploadWebURL != nil },
            set: { if !$0 { mergedUploadWebURL = nil } }
        )) {
            if let urlString = mergedUploadWebURL, let url = URL(string: urlString) {
                Link("View on Strava", destination: url)
            }
            Button("OK") { mergedUploadWebURL = nil }
        } message: {
            Text("The selected rides were merged into one activity.")
        }
        .onAppear {
            hasStravaAuth = KeychainHelper.loadTokens(for: .strava) != nil
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
        HStack(spacing: 8) {
            Button {
                navigateToMulti = true
            } label: {
                Label("View", systemImage: "arrow.triangle.merge")
                    .labelStyle(.iconOnly)
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.blue)
            .disabled(selectedIDs.isEmpty)

            Menu {
                Button {
                    exportSelectedAsZip()
                } label: {
                    Label("Export GPX ZIP", systemImage: "doc.zipper")
                }

                if hasStravaAuth {
                    Button {
                        uploadMergedToStrava()
                    } label: {
                        Label("Upload Merged to Strava", systemImage: "figure.outdoor.cycle")
                    }
                }
            } label: {
                Label("Export", systemImage: "square.and.arrow.up")
                    .frame(maxWidth: .infinity, minHeight: 36)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(selectedIDs.isEmpty || isExportingZip || isUploadingMerged)

            Button(role: .destructive) {
                showDeleteConfirm = true
            } label: {
                Label("Delete", systemImage: "trash")
                    .labelStyle(.iconOnly)
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

    private func exportSelectedAsZip() {
        let rides = selectedRides
        guard !rides.isEmpty else { return }
        isExportingZip = true
        let store = rideStore
        DispatchQueue.global(qos: .userInitiated).async {
            let url = store.exportZipGPX(rides: rides)
            DispatchQueue.main.async {
                isExportingZip = false
                if let url {
                    exportZipURL = url
                    showExportShareSheet = true
                }
            }
        }
    }

    private func uploadMergedToStrava() {
        let rides = selectedRides
        guard !rides.isEmpty else { return }
        isUploadingMerged = true
        Task {
            do {
                let webURL = try await UploadManager.shared.uploadMergedToStrava(rides)
                await MainActor.run {
                    isUploadingMerged = false
                    mergedUploadWebURL = webURL
                }
            } catch {
                await MainActor.run {
                    isUploadingMerged = false
                    mergedUploadError = error.localizedDescription
                }
            }
        }
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
