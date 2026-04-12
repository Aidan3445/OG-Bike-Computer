//
//  ActivityTypeEnum.swift
//  OG Bike Computer
//
//  AppEnum wrapper for ActivityType, used as a parameter in App Intents.
//  Kept separate from the main ActivityType to avoid Sendable/MainActor conflicts.
//

import AppIntents

enum ActivityTypeEnum: String, AppEnum {
    case cycling
    case running
    case walking
    case hiking

    static var typeDisplayRepresentation = TypeDisplayRepresentation(name: "Activity Type")

    static var caseDisplayRepresentations: [ActivityTypeEnum: DisplayRepresentation] = [
        .cycling: "Cycling",
        .running: "Running",
        .walking: "Walking",
        .hiking: "Hiking"
    ]

    var activityType: ActivityType {
        ActivityType(rawValue: rawValue) ?? .cycling
    }
}
