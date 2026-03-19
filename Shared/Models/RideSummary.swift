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
    let name: String
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
}
