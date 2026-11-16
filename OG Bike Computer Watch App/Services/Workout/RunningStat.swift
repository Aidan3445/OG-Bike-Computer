//
//  RunningStat.swift
//  OG Bike Computer Watch App
//

import Foundation

/// Sum, count and max of a stream of samples, for ride and split averages.
struct RunningStat {
    private(set) var sum: Double = 0
    private(set) var count = 0
    private(set) var max: Double = 0

    var average: Double { count > 0 ? sum / Double(count) : 0 }

    init(sum: Double = 0, count: Int = 0, max: Double = 0) {
        self.sum = sum
        self.count = count
        self.max = max
    }

    mutating func add(_ value: Double) {
        sum += value
        count += 1
        if value > max { max = value }
    }
}
