//
//  TurnNotificationManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/28/26.
//

import Foundation
import UserNotifications

class TurnNotificationManager {
    static let shared = TurnNotificationManager()

    private var notificationCounter: Int = 0
    private var postedIdentifiers: [String] = []

    private init() {}

    // MARK: - Permissions

    func requestPermission() {
        UNUserNotificationCenter.current().requestAuthorization(
            options: [.alert, .sound]
        ) { granted, error in
            if let error {
                print("[TurnNotif] Permission error: \(error)")
            }
            print("[TurnNotif] Permission granted: \(granted)")
        }
    }

    // MARK: - Post / Update

    /// Posts a navigation notification with a unique identifier.
    /// All turn alerts use `.timeSensitive` to wake the phone screen.
    func post(text: String) {
        notificationCounter += 1
        let identifier = "bike-nav-turn-\(notificationCounter)"
        postedIdentifiers.append(identifier)

        let content = UNMutableNotificationContent()
        content.title = "Navigation"
        content.body = text
        content.threadIdentifier = "bike-navigation"
        content.interruptionLevel = .timeSensitive
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil // deliver immediately
        )

        UNUserNotificationCenter.current().add(request) { error in
            if let error {
                print("[TurnNotif] Post error: \(error)")
            }
        }
    }

    /// Posts an off-route notification
    func postOffRoute(message: String) {
        notificationCounter += 1
        let identifier = "bike-nav-offroute-\(notificationCounter)"
        postedIdentifiers.append(identifier)

        let content = UNMutableNotificationContent()
        content.title = "Off Route"
        content.body = message
        content.threadIdentifier = "bike-navigation"
        content.interruptionLevel = .timeSensitive
        content.sound = nil

        let request = UNNotificationRequest(
            identifier: identifier,
            content: content,
            trigger: nil
        )

        UNUserNotificationCenter.current().add(request)
    }

    // MARK: - Cleanup

    func clearAll() {
        UNUserNotificationCenter.current().removeDeliveredNotifications(
            withIdentifiers: postedIdentifiers
        )
        UNUserNotificationCenter.current().removePendingNotificationRequests(
            withIdentifiers: postedIdentifiers
        )
        postedIdentifiers.removeAll()
        notificationCounter = 0
    }
}
