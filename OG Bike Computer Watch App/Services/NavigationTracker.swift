//
//  NavigationTracker.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation
import Combine

class NavigationTracker: ObservableObject {
    @Published var distanceAlongRoute: Double = 0
    @Published var distanceToNextTurn: Double = 0
    @Published var nextTurn: TurnPoint?
    @Published var currentSegmentIndex: Int = 0
    @Published var isOffRoute: Bool = false
    @Published var isRouteComplete: Bool = false
    @Published var distanceRemaining: Double = 0
    @Published var currentBearing: Double = 0

    let offRouteThreshold: Double = 100
    let completionThreshold: Double = 50

    let turnWarningDistance: Double = 200
    let turnAlertDistance: Double = 50

    private(set) var route: ProcessedRoute?
    var processedRoute: ProcessedRoute? { route }
    private var lastSearchIndex: Int = 0

    func load(_ processedRoute: ProcessedRoute) {
        route = processedRoute
        lastSearchIndex = 0
        distanceAlongRoute = 0
        distanceToNextTurn = 0
        nextTurn = nil
        currentSegmentIndex = 0
        isOffRoute = false
        isRouteComplete = false
        distanceRemaining = processedRoute.totalDistance
        currentBearing = processedRoute.points.first?.bearingToNext ?? 0
    }

    func update(location: CLLocation) -> TurnAlert? {
        guard let route = route, route.points.count >= 2 else { return nil }

        let (nearestIndex, nearestDistance) = findNearest(
            location: location,
            in: route,
            searchCenter: lastSearchIndex
        )

        isOffRoute = nearestDistance > offRouteThreshold

        guard !isOffRoute else { return nil }

        lastSearchIndex = nearestIndex
        currentSegmentIndex = nearestIndex

        distanceAlongRoute = interpolateDistance(
            location: location,
            nearestIndex: nearestIndex,
            route: route)

        distanceRemaining = route.totalDistance - distanceAlongRoute
        currentBearing = route.points[nearestIndex].bearingToNext

        if distanceRemaining < completionThreshold {
            isRouteComplete = true
            nextTurn = nil
            distanceToNextTurn = 0
            return nil
        }

        let previousTurn = nextTurn
        let previousDistance = distanceToNextTurn

        nextTurn = route.turnPoints.first { $0.distanceFromStart > distanceAlongRoute }
        distanceToNextTurn = nextTurn.map { $0.distanceFromStart - distanceAlongRoute } ?? 0

        return checkTurnAlert(
            previousTurn: previousTurn,
            previousDistance: previousDistance
        )
    }

    private func findNearest(
        location: CLLocation,
        in route: ProcessedRoute,
        searchCenter: Int
    ) -> (index: Int, distance: Double) {
        let searchRadius = 50
        let start = max(0, searchCenter - searchRadius)
        let end = min(route.points.count - 1, searchCenter + searchRadius)

        var bestIndex = searchCenter
        var bestDistance = Double.greatestFiniteMagnitude

        for i in start...end {
            let point = route.points[i]
            let pointLoc = CLLocation(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude)
            let dist = location.distance(from: pointLoc)
            if dist < bestDistance {
                bestDistance = dist
                bestIndex = i
            }
        }

        if bestIndex == start || bestIndex == end {
            for i in 0..<route.points.count {
                let point = route.points[i]
                let pointLoc = CLLocation(
                    latitude: point.coordinate.latitude,
                    longitude: point.coordinate.longitude)
                let dist = location.distance(from: pointLoc)
                if dist < bestDistance {
                    bestDistance = dist
                    bestIndex = i
                }
            }
        }

        return (bestIndex, bestDistance)
    }

    private func interpolateDistance(
        location: CLLocation,
        nearestIndex: Int,
        route: ProcessedRoute
    ) -> Double {
        let baseDist = route.points[nearestIndex].distanceFromStart

        if nearestIndex < route.points.count - 1 {
            let curr = route.points[nearestIndex]
            let next = route.points[nearestIndex + 1]
            let segLen = next.distanceFromStart - curr.distanceFromStart
            guard segLen > 0 else { return baseDist }

            let currLoc = CLLocation(
                latitude: curr.coordinate.latitude,
                longitude: curr.coordinate.longitude)
            let nextLoc = CLLocation(
                latitude: next.coordinate.latitude,
                longitude: next.coordinate.longitude)

            let totalDist = currLoc.distance(from: nextLoc)
            let distFromCurr = location.distance(from: currLoc)
            let distFromNext = location.distance(from: nextLoc)

            guard totalDist > 0 else { return baseDist }

            let cosAngle = (distFromCurr * distFromCurr + totalDist * totalDist - distFromNext * distFromNext)
                / (2 * distFromCurr * totalDist)
            let projection = distFromCurr * max(-1, min(1, cosAngle))
            let ratio = max(0, min(1, projection / totalDist))

            return baseDist + segLen * ratio
        }

        return baseDist
    }

    enum TurnAlert {
        case warning(TurnPoint)
        case imminent(TurnPoint)
    }

    private var lastAlertedTurnIndex: Int?
    private var lastAlertLevel: TurnAlert?

    private func checkTurnAlert(
        previousTurn: TurnPoint?,
        previousDistance: Double
    ) -> TurnAlert? {
        guard let turn = nextTurn else { return nil }

        if turn.index != lastAlertedTurnIndex {
            lastAlertedTurnIndex = nil
        }

        if distanceToNextTurn <= turnAlertDistance {
            if lastAlertedTurnIndex != turn.index || !(lastAlertLevel.isImminent) {
                lastAlertedTurnIndex = turn.index
                lastAlertLevel = .imminent(turn)
                return .imminent(turn)
            }
        }
        else if distanceToNextTurn <= turnWarningDistance {
            if lastAlertedTurnIndex != turn.index {
                lastAlertedTurnIndex = turn.index
                lastAlertLevel = .warning(turn)
                return .warning(turn)
            }
        }

        return nil
    }
}

extension Optional where Wrapped == NavigationTracker.TurnAlert {
    var isImminent: Bool {
        if case .imminent = self { return true }
        return false
    }
}
