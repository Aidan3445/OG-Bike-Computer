//
//  RideHistoryView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI

struct RideHistoryView: View {
    @ObservedObject var rideStore: RideStore

    var body: some View {
        Group {
            if rideStore.rides.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "bicycle",
                    description: Text("Completed rides from your watch will appear here."))
            } else {
                List {
                    ForEach(rideStore.rides) { ride in
                        NavigationLink {
                            RideDetailView(ride: ride, rideStore: rideStore)
                        } label: {
                            RideRow(ride: ride, rideStore: rideStore)
                        }
                    }
                    .onDelete { indices in
                        for i in indices {
                            rideStore.delete(rideStore.rides[i])
                        }
                    }
                }
            }
        }
        .navigationTitle("Rides")
    }
}
