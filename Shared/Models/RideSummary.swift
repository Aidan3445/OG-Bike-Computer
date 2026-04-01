//
//  RideSummary.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/1/26.
//

import Foundation
import UIKit

struct RideSummary: Codable, Identifiable {
    let id: UUID
    var name: String
    let activityType: ActivityType
    let date: Date
    let elapsedTime: TimeInterval
    let movingTime: TimeInterval
    let distance: Double
    let calories: Double
    let elevationGain: Double
    let elevationLoss: Double
    let avgSpeed: Double
    let pointCount: Int

    let trackFilename: String

    // Extended stats (optional for backward compat with old rides)
    let maxSpeed: Double?
    let avgPower: Double?
    let maxPower: Double?
    let avgHeartRate: Double?
    let maxHeartRate: Double?
    let highestElevation: Double?
    let lowestElevation: Double?
    var uploads: [ServiceUploadRecord]?

    init(id: UUID, name: String, activityType: ActivityType, date: Date,
         elapsedTime: TimeInterval, movingTime: TimeInterval, distance: Double,
         calories: Double, elevationGain: Double, elevationLoss: Double,
         avgSpeed: Double, pointCount: Int, trackFilename: String,
         maxSpeed: Double? = nil, avgPower: Double? = nil, maxPower: Double? = nil,
         avgHeartRate: Double? = nil, maxHeartRate: Double? = nil,
         highestElevation: Double? = nil, lowestElevation: Double? = nil,
         uploads: [ServiceUploadRecord]? = nil) {
        self.id = id
        self.name = name
        self.activityType = activityType
        self.date = date
        self.elapsedTime = elapsedTime
        self.movingTime = movingTime
        self.distance = distance
        self.calories = calories
        self.elevationGain = elevationGain
        self.elevationLoss = elevationLoss
        self.avgSpeed = avgSpeed
        self.pointCount = pointCount
        self.trackFilename = trackFilename
        self.maxSpeed = maxSpeed
        self.avgPower = avgPower
        self.maxPower = maxPower
        self.avgHeartRate = avgHeartRate
        self.maxHeartRate = maxHeartRate
        self.highestElevation = highestElevation
        self.lowestElevation = lowestElevation
        self.uploads = uploads
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        activityType = try container.decode(ActivityType.self, forKey: .activityType)
        date = try container.decode(Date.self, forKey: .date)
        elapsedTime = try container.decode(TimeInterval.self, forKey: .elapsedTime)
        movingTime = try container.decode(TimeInterval.self, forKey: .movingTime)
        distance = try container.decode(Double.self, forKey: .distance)
        calories = try container.decode(Double.self, forKey: .calories)
        elevationGain = try container.decode(Double.self, forKey: .elevationGain)
        elevationLoss = try container.decode(Double.self, forKey: .elevationLoss)
        avgSpeed = try container.decode(Double.self, forKey: .avgSpeed)
        pointCount = try container.decode(Int.self, forKey: .pointCount)
        trackFilename = try container.decode(String.self, forKey: .trackFilename)
        // Optional fields — old rides won't have these
        maxSpeed = try container.decodeIfPresent(Double.self, forKey: .maxSpeed)
        avgPower = try container.decodeIfPresent(Double.self, forKey: .avgPower)
        maxPower = try container.decodeIfPresent(Double.self, forKey: .maxPower)
        avgHeartRate = try container.decodeIfPresent(Double.self, forKey: .avgHeartRate)
        maxHeartRate = try container.decodeIfPresent(Double.self, forKey: .maxHeartRate)
        highestElevation = try container.decodeIfPresent(Double.self, forKey: .highestElevation)
        lowestElevation = try container.decodeIfPresent(Double.self, forKey: .lowestElevation)
        uploads = try container.decodeIfPresent([ServiceUploadRecord].self, forKey: .uploads)
    }
}
