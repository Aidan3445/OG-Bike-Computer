//
//  RideHistoryView.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/2/26.
//

import SwiftUI

struct RideHistoryView: View {
    @ObservedObject var rideStore: RideStore

    private var sections: [(DateSection, [RideSummary])] {
        DateSection.group(rideStore.rides, by: \.date)
    }

    var body: some View {
        Group {
            if rideStore.rides.isEmpty {
                ContentUnavailableView(
                    "No Rides Yet",
                    systemImage: "bicycle",
                    description: Text("Completed rides from your watch will appear here."))
            } else {
                List {
                    ForEach(sections, id: \.0) { section, rides in
                        Section {
                            ForEach(rides) { ride in
                                NavigationLink {
                                    RideDetailView(ride: ride, rideStore: rideStore)
                                } label: {
                                    RideRow(ride: ride, onRename: { newName in
                                        rideStore.rename(ride, to: newName)
                                    })
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
