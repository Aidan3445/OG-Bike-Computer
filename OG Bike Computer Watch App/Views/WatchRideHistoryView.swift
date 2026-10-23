//
//  WatchRideHistoryView.swift
//  OG Bike Computer Watch App
//
//  Second page of the watch main view. Lists rides currently on the watch with
//  their transfer status. Tap a non-transferred ride to retry the transfer.
//  Discarded rides show with an "Undiscard" swipe action and a delete countdown.
//

import SwiftUI

struct WatchRideHistoryView: View {
    @ObservedObject var rideStore: RideStore
    @ObservedObject var connectivity: ConnectivityManager

    var body: some View {
        NavigationStack {
            Group {
                if visibleRides.isEmpty {
                    ScrollView {
                        VStack(spacing: 8) {
                            Image(systemName: "clock.arrow.circlepath")
                                .font(.largeTitle)
                                .foregroundStyle(.secondary)
                            Text("No Rides")
                                .font(.headline)
                            Text("Completed rides waiting to transfer will show here.")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                    }
                } else {
                    List {
                        ForEach(visibleRides) { ride in
                            row(for: ride)
                        }
                    }
                    .navigationTitle("History")
                }
            }
        }
    }

    /// Held rides belong on the routes page, not here.
    private var visibleRides: [RideSummary] {
        rideStore.rides
            .filter { !$0.onHold }
            .sorted { $0.date > $1.date }
    }

    @ViewBuilder
    private func row(for ride: RideSummary) -> some View {
        let status = connectivity.transferStatus(for: ride.id)
        let isInFlight = connectivity.inFlightTransferRideIDs.contains(ride.id)
        let presence = connectivity.phonePresenceByRide[ride.id] ?? .unknown
        Button {
            // Tap behavior:
            //   • pending → retry transfer
            //   • confirmed but reported missing on phone → retry transfer
            //   • discarded → undiscard
            //   • confirmed + present → no-op
            if isInFlight { return }
            switch status {
            case .pending, .unknown:
                connectivity.retryTransfer(rideID: ride.id)
            case .confirmed:
                if presence == .missing {
                    connectivity.retryTransfer(rideID: ride.id)
                }
            case .discarded:
                connectivity.undiscardRide(rideID: ride.id)
            }
        } label: {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    statusIcon(for: status, ride: ride, isInFlight: isInFlight, presence: presence)
                    Text(ride.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                Text(formatDistance(ride.distance))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                statusLine(for: status, ride: ride, isInFlight: isInFlight, presence: presence)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)
        .onAppear {
            // List rows on watchOS are lazily materialized — `.onAppear` fires
            // when the row scrolls into view, so we only verify rides the user
            // actually sees. Cached results short-circuit inside the manager.
            if case .confirmed = status, !ride.discarded {
                connectivity.verifyPhonePresence(rideID: ride.id)
            }
        }
    }

    @ViewBuilder
    private func statusIcon(
        for status: TransferLedger.Status,
        ride: RideSummary,
        isInFlight: Bool,
        presence: ConnectivityManager.PhonePresence
    ) -> some View {
        if ride.discarded {
            Image(systemName: "trash.fill")
                .foregroundStyle(.red)
        } else if isInFlight {
            ProgressView()
                .controlSize(.mini)
        } else {
            switch status {
            case .confirmed:
                switch presence {
                case .missing:
                    Image(systemName: "exclamationmark.icloud")
                        .foregroundStyle(.red)
                case .checking:
                    ProgressView()
                        .controlSize(.mini)
                case .present, .unknown:
                    Image(systemName: "checkmark.icloud.fill")
                        .foregroundStyle(.green)
                }
            case .pending, .unknown:
                Image(systemName: "arrow.up.circle")
                    .foregroundStyle(.orange)
            case .discarded:
                Image(systemName: "trash.fill")
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private func statusLine(
        for status: TransferLedger.Status,
        ride: RideSummary,
        isInFlight: Bool,
        presence: ConnectivityManager.PhonePresence
    ) -> some View {
        if ride.discarded {
            if case .discarded(let deletesAt) = status {
                Text("Tap to undiscard • \(deletesInText(deletesAt))")
            } else {
                Text("Tap to undiscard")
            }
        } else if isInFlight {
            Text("Transferring…")
        } else {
            switch status {
            case .confirmed(let deletesAt):
                switch presence {
                case .missing:
                    Text("Not on phone • Tap to retry")
                case .checking:
                    Text("Verifying…")
                case .present, .unknown:
                    Text("Transferred • \(deletesInText(deletesAt))")
                }
            case .pending(let deletesAt):
                Text("Tap to retry • \(deletesInText(deletesAt))")
            case .discarded(let deletesAt):
                Text("Discarded • \(deletesInText(deletesAt))")
            case .unknown:
                Text("Tap to send")
            }
        }
    }

    private func deletesInText(_ date: Date) -> String {
        let secondsLeft = date.timeIntervalSinceNow
        guard secondsLeft > 0 else { return "Deletes soon" }
        let daysLeft = Int(ceil(secondsLeft / 86400))
        if daysLeft <= 1 { return "Deletes in <1d" }
        return "Deletes in \(daysLeft)d"
    }
}

private extension ConnectivityManager {
    /// Bridge helper so SwiftUI views can call `connectivity.transferStatus(...)`
    /// without importing TransferLedger directly.
    func transferStatus(for rideID: UUID) -> TransferLedger.Status {
        TransferLedger.shared.status(for: rideID)
    }
}
