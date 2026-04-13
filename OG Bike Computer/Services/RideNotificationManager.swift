//
//  RideNotificationManager.swift
//  OG Bike Computer
//
//  Posts local notifications for ride lifecycle events — ride ended, ride saved,
//  Strava auto-upload skipped, etc.  Used when UI dialogs aren't visible
//  (e.g. from a LiveActivity button or background auto-upload flow).
//

import Foundation
import UserNotifications

class RideNotificationManager {
    static let shared = RideNotificationManager()
    private init() {}

    // MARK: - Ride Ended (from LiveActivity end button)

    /// Posted after the app processes an "end" command from the Live Activity widget.
    func postRideEnded() {
        post(
            title: "Ride Ended",
            body: "Your ride has been saved.",
            identifier: "ride-ended"
        )
    }

    /// Posted after a short ride is discarded from the Live Activity widget.
    func postRideDiscarded() {
        post(
            title: "Ride Discarded",
            body: "Ride was under 1 minute and has been discarded.",
            identifier: "ride-discarded"
        )
    }

    // MARK: - Strava Auto-Upload Skipped

    /// Posted when a ride is too short for Strava auto-upload.
    /// The ride is still saved locally — the user can upload manually from ride details.
    func postShortRideSkipped(_ ride: RideSummary) {
        let distMi = ride.distance / 1609.34
        post(
            title: "Ride Saved",
            body: String(format: "%.2f mi ride saved but not uploaded to Strava (under 0.1 mi). You can upload manually from ride details.", distMi),
            identifier: "ride-short-skip-\(ride.id.uuidString)"
        )
    }

    // MARK: - Private

    private func post(title: String, body: String, identifier: String) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.interruptionLevel = .timeSensitive

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[RideNotif] Post error: \(error)")
            }
        }
    }
}
