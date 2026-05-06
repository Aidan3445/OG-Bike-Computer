//
//  RideHistoryView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI

struct RideHistoryView: View {
    @ObservedObject var rideStore: RideStore
    @ObservedObject private var connectivity = ConnectivityManager.shared

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
    private var showAwaitingPlaceholder: Bool {
        connectivity.isAwaitingIncomingRide &&
            connectivity.pendingTransferRideIDs.isEmpty
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
                            }
                        } header: {
                            Text("On Hold")
                                .foregroundStyle(.orange)
                        }
                    }

                    ForEach(sections, id: \.0) { section, rides in
                        Section {
                            ForEach(rides) { ride in
                                let isTransferring = connectivity.pendingTransferRideIDs.contains(ride.id)
                                if isTransferring {
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
                            .onDelete { indices in
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
        .navigationTitle("Rides")
    }
}
