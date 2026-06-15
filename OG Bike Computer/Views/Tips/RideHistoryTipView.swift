//
//  RideHistoryTipView.swift
//  OG Bike Computer
//
//  Explains the on-watch ride history page: transfer states, recovery window,
//  and the per-bucket retention policy enforced by TransferLedger.
//

import SwiftUI

struct RideHistoryTipView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(spacing: 6) {
                    Image(systemName: "clock.arrow.circlepath")
                        .font(.system(size: 48))
                        .foregroundStyle(.teal)
                    Text("Watch Ride History")
                        .font(.title2)
                        .bold()
                    Text("Every ride stays on your watch for a grace period after recording, so a missed transfer or accidental discard isn't a lost ride.")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

                // How to open it
                VStack(alignment: .leading, spacing: 10) {
                    Label("Opening the history", systemImage: "applewatch.watchface")
                        .font(.headline)
                        .foregroundStyle(.teal)

                    TipRow(
                        icon: "digitalcrown.horizontal.arrow.counterclockwise",
                        color: .teal,
                        title: "Turn the Crown down",
                        detail: "From the Routes screen on the watch, scroll the Digital Crown down to switch to the ride history page."
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Indicators
                VStack(alignment: .leading, spacing: 10) {
                    Label("Status indicators", systemImage: "circle.hexagongrid.fill")
                        .font(.headline)
                        .foregroundStyle(.purple)

                    TipRow(
                        icon: "checkmark.icloud.fill",
                        color: .green,
                        title: "Transferred",
                        detail: "The phone has acknowledged this ride. Verified again when the row appears in case the file was lost or deleted on the phone."
                    )
                    TipRow(
                        icon: "arrow.up.circle",
                        color: .orange,
                        title: "Not yet transferred",
                        detail: "Recorded on the watch but not confirmed by the phone yet. Tap the row to manually re-send."
                    )
                    TipRow(
                        icon: "exclamationmark.icloud",
                        color: .red,
                        title: "Missing on phone",
                        detail: "The ride was marked transferred but the phone no longer has the file. Tap the row to re-send."
                    )
                    TipRow(
                        icon: "trash.fill",
                        color: .red,
                        title: "Discarded",
                        detail: "A held ride you chose to discard. Tap the row on the watch to undiscard and send it to the phone."
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))

                // Retention
                VStack(alignment: .leading, spacing: 10) {
                    Label("How long things stick around", systemImage: "calendar")
                        .font(.headline)
                        .foregroundStyle(.blue)

                    TipRow(
                        icon: "checkmark.icloud.fill",
                        color: .green,
                        title: "7 days after transfer",
                        detail: "Confirmed rides stay on the watch for 7 days after the phone acknowledges them. Within that window you can recover a ride you accidentally deleted from the phone — open the watch history and the row will show \"Missing on phone\". Tap it to re-send."
                    )
                    TipRow(
                        icon: "arrow.up.circle",
                        color: .orange,
                        title: "30 days if never transferred",
                        detail: "If the phone never acknowledges a ride, the watch keeps it for 30 days. Connect the watch to the paired iPhone any time inside that window — the transfer retries automatically."
                    )
                    TipRow(
                        icon: "trash.fill",
                        color: .red,
                        title: "7 days after discarding",
                        detail: "Discarded held rides aren't deleted right away. They sit in the watch history for 7 days so you can undiscard if it was a mistake."
                    )
                }
                .padding()
                .background(.ultraThinMaterial)
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal)
            .padding(.bottom)
        }
        .navigationTitle("Watch Ride History")
        .navigationBarTitleDisplayMode(.inline)
    }
}
