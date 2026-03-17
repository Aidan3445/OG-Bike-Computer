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
    @Published var distanceToEndpoint: Double = 0
    @Published var missedTurn: TurnPoint?
    @Published var nearestRouteDistance: Double = 0 // GPS distance to nearest route point
    @Published var bearingToRoute: Double = 0       // bearing from rider back to nearest route point

    private var wasOffRoute = false
    private var lastPassedTurn: TurnPoint?
    private var offRouteLocation: CLLocation?
    let missedTurnProximity: Double = 150 // if off-route within this distance of a turn, it's a missed turn

    let offRouteThreshold: Double = 100
    let rejoinThreshold: Double = 30 // must be this close to rejoin after going off-route

    let turnWarningDistance: Double = 500
    let turnAlertDistance: Double = 50
    let turnConfirmationBuffer: Double = 40 // must pass turn by this much before advancing to next

    // Two-zone completion: must enter outer zone, leave inner zone, then re-enter inner zone
    let endZoneOuter: Double = 75   // ~250ft — arms completion
    let endZoneInner: Double = 30   // ~100ft — triggers completion
    var canCompleteRoute: Bool = false
    var hasJoinedRoute: Bool = false
    let minDistanceForCompletion: Double = 402

    private(set) var route: ProcessedRoute?
    var processedRoute: ProcessedRoute? { route }
    private var lastSearchIndex: Int = 0
    private var endpointLocation: CLLocation?

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
        distanceToEndpoint = 0
        canCompleteRoute = false
        hasJoinedRoute = false
        wasOffRoute = false
        lastPassedTurn = nil
        missedTurn = nil
        offRouteLocation = nil
        nearestRouteDistance = 0
        bearingToRoute = 0

        if let last = processedRoute.points.last {
            endpointLocation = CLLocation(
                latitude: last.coordinate.latitude,
                longitude: last.coordinate.longitude)
        }
    }
    
    func anchorToLocation(_ location: CLLocation) {
        guard let route = route, route.points.count >= 2 else { return }

        // Full-route scan — no search window restriction
        var bestIndex = 0
        var bestDistance = Double.greatestFiniteMagnitude

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

        lastSearchIndex = bestIndex
        currentSegmentIndex = bestIndex
        distanceAlongRoute = route.points[bestIndex].distanceFromStart
        distanceRemaining = route.totalDistance - distanceAlongRoute

        // If we're reasonably close, consider the route joined
        // so the search window works normally from here
        if bestDistance <= offRouteThreshold {
            hasJoinedRoute = true
        }

        print("[Nav] Anchored to segment \(bestIndex) "
            + "(\(Int(distanceAlongRoute))m along, "
            + "\(Int(bestDistance))m away)")
    }

    func reset() {
        route = nil
        lastSearchIndex = 0
        endpointLocation = nil
        distanceAlongRoute = 0
        distanceToNextTurn = 0
        nextTurn = nil
        currentSegmentIndex = 0
        isOffRoute = false
        isRouteComplete = false
        distanceRemaining = 0
        currentBearing = 0
        distanceToEndpoint = 0
        canCompleteRoute = false
        hasJoinedRoute = false
        wasOffRoute = false
        lastPassedTurn = nil
        missedTurn = nil
        offRouteLocation = nil
        nearestRouteDistance = 0
        bearingToRoute = 0
        lastAlertedTurnIndex = nil
        lastAlertLevel = nil
    }

    func update(location: CLLocation) -> TurnAlert? {
        guard let route = route, route.points.count >= 2 else { return nil }

        let (nearestIndex, nearestDistance) = findNearest(
            location: location,
            in: route,
            searchCenter: lastSearchIndex
        )

        isOffRoute = nearestDistance > offRouteThreshold
        nearestRouteDistance = nearestDistance

        // Hysteresis: once off-route, must come much closer to rejoin
        if wasOffRoute && nearestDistance > rejoinThreshold {
            isOffRoute = true
        }

        // Always update tracking so the nearest point stays fresh
        lastSearchIndex = nearestIndex
        currentSegmentIndex = nearestIndex

        // Off-route transition detection
        if isOffRoute && !wasOffRoute {
            offRouteLocation = location
            missedTurn = findMissedTurn(at: location, in: route)
        } else if !isOffRoute && wasOffRoute {
            missedTurn = nil
            offRouteLocation = nil
        }
        wasOffRoute = isOffRoute

        // When off-route, compute bearing back to nearest route point
        if isOffRoute {
            let nearestPoint = route.points[nearestIndex]
            bearingToRoute = RouteProcessor.bearing(
                from: location.coordinate,
                to: nearestPoint.coordinate)
            return nil
        }

        distanceAlongRoute = interpolateDistance(
            location: location,
            nearestIndex: nearestIndex,
            route: route)

        distanceRemaining = route.totalDistance - distanceAlongRoute
        currentBearing = route.points[nearestIndex].bearingToNext

        // Endpoint proximity (GPS distance, not route distance)
        if let endpoint = endpointLocation {
            distanceToEndpoint = location.distance(from: endpoint)
        }

        // Zone logic: arm completion when inside outer zone but outside inner zone
        // This means you've been "near" the end but not "at" it yet
        if distanceToEndpoint <= endZoneOuter && distanceToEndpoint > endZoneInner {
            canCompleteRoute = true
        }

        // Complete when armed, inside inner zone, AND traveled minimum distance along route
        if canCompleteRoute && distanceToEndpoint <= endZoneInner && distanceAlongRoute >= minDistanceForCompletion {
            isRouteComplete = true
            nextTurn = nil
            distanceToNextTurn = 0
            return nil
        }

        let previousTurn = nextTurn
        let previousDistance = distanceToNextTurn

        let newNextTurn = route.turnPoints.first { $0.distanceFromStart > distanceAlongRoute - turnConfirmationBuffer }
        if let prev = nextTurn, newNextTurn?.index != prev.index {
            lastPassedTurn = prev
        }
        nextTurn = newNextTurn
        distanceToNextTurn = nextTurn.map { max(0, $0.distanceFromStart - distanceAlongRoute) } ?? 0

        return checkTurnAlert(
            previousTurn: previousTurn,
            previousDistance: previousDistance
        )
    }

    // Called by VoiceNavigator after announcing arrival — disarms so it won't re-trigger
    func resetCompletion() {
        canCompleteRoute = false
        isRouteComplete = false
    }

    // Distance-based search window: only consider points within this route-distance
    // of the current position. Prevents snapping to geographically close but
    // route-distant points (e.g. end of a loop).
    private let searchWindowMeters: Double = 500

    private func findNearest(
        location: CLLocation,
        in route: ProcessedRoute,
        searchCenter: Int
    ) -> (index: Int, distance: Double) {
        let currentRouteDist = route.points[max(0, min(searchCenter, route.points.count - 1))].distanceFromStart

        // Define the route-distance window to search
        let minRouteDist = max(0, currentRouteDist - searchWindowMeters)
        let maxRouteDist: Double
        if hasJoinedRoute {
            maxRouteDist = min(route.totalDistance, currentRouteDist + searchWindowMeters)
        } else {
            // Before joining, only look at the first portion of the route
            maxRouteDist = min(route.totalDistance, searchWindowMeters)
        }

        var bestIndex = max(0, min(searchCenter, route.points.count - 1))
        var bestDistance = Double.greatestFiniteMagnitude

        for i in 0..<route.points.count {
            let pointDist = route.points[i].distanceFromStart
            guard pointDist >= minRouteDist && pointDist <= maxRouteDist else { continue }

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

        if bestDistance <= offRouteThreshold {
            if !hasJoinedRoute { hasJoinedRoute = true }
            return (bestIndex, bestDistance)
        }

        // Off-route before joining: stay anchored
        if !hasJoinedRoute {
            return (bestIndex, bestDistance)
        }

        // Off-route after joining: full scan with heading + forward bias
        let riderCourse = location.course
        var fullBestIndex = bestIndex
        var fullBestScore = Double.greatestFiniteMagnitude
        var fullBestDistance = bestDistance

        for i in 0..<route.points.count {
            let point = route.points[i]
            let pointLoc = CLLocation(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude)
            let dist = location.distance(from: pointLoc)

            var score = dist

            if riderCourse >= 0 {
                let bearingDiff = abs(headingDelta(riderCourse, point.bearingToNext))
                score += (bearingDiff / 180.0) * 50
            }

            // Prefer points near current route distance over distant jumps
            let routeDistDelta = abs(point.distanceFromStart - currentRouteDist)
            score += min(routeDistDelta * 0.05, 50)

            if score < fullBestScore {
                fullBestScore = score
                fullBestIndex = i
                fullBestDistance = dist
            }
        }

        return (fullBestIndex, fullBestDistance)
    }

    private func headingDelta(_ a: Double, _ b: Double) -> Double {
        var delta = b - a
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    // Check if the rider went off-route near a turn they should have taken
    private func findMissedTurn(at location: CLLocation, in route: ProcessedRoute) -> TurnPoint? {
        // Check the most recently passed turn
        if let turn = lastPassedTurn {
            let turnLoc = CLLocation(latitude: turn.coordinate.latitude, longitude: turn.coordinate.longitude)
            if location.distance(from: turnLoc) < missedTurnProximity {
                return turn
            }
        }

        // Check the upcoming turn (rider might have gone straight instead of turning)
        if let turn = nextTurn {
            let turnLoc = CLLocation(latitude: turn.coordinate.latitude, longitude: turn.coordinate.longitude)
            if location.distance(from: turnLoc) < missedTurnProximity {
                return turn
            }
        }

        return nil
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
            if lastAlertedTurnIndex != turn.index || !isImminentAlert(lastAlertLevel) {
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
    private func isImminentAlert(_ alert: TurnAlert?) -> Bool {
        if case .imminent = alert { return true }
        return false
    }
}
