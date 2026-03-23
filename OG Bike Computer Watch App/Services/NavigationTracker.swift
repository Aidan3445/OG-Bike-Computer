//
//  NavigationTracker.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation
import CoreLocation
import Combine

struct RejoinCandidate {
    let segmentIndex: Int
    let coordinate: CLLocationCoordinate2D
    let distance: Double // GPS distance from rider
}

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
    @Published var nearestRouteDistance: Double = 0
    @Published var bearingToRoute: Double = 0
    @Published var rejoinCandidates: [RejoinCandidate] = []
    @Published var showReversePrompt: Bool = false
    @Published var turnMode: TurnMode = .calculated

    /// The active turn list based on the current turn mode.
    var activeTurnPoints: [TurnPoint] {
        guard let route = route else { return [] }
        return route.turnPoints(for: turnMode)
    }

    private var wasOffRoute = false
    private var lastPassedTurn: TurnPoint?
    private var offRouteLocation: CLLocation?
    let missedTurnProximity: Double = 150

    let offRouteThreshold: Double = 100
    let rejoinThreshold: Double = 30

    let turnWarningDistance: Double = 500
    let turnAlertDistance: Double = 50
    let turnConfirmationBuffer: Double = 40

    let endZoneOuter: Double = 75
    let endZoneInner: Double = 30
    var canCompleteRoute: Bool = false
    var hasJoinedRoute: Bool = false
    let minDistanceForCompletion: Double = 402

    private(set) var route: ProcessedRoute?
    var processedRoute: ProcessedRoute? { route }
    private var lastSearchIndex: Int = 0
    private var endpointLocation: CLLocation?

    // Double-back detection: tracks a sustained alternate section match
    private var alternateCandidate: (index: Int, sampleCount: Int)?
    private let alternateDwellThreshold = 12 // consecutive samples before jumping
    private var reversePromptDismissed = false

    func load(_ processedRoute: ProcessedRoute) {
        route = processedRoute
        turnMode = processedRoute.hasWaypoints ? .provided : .calculated
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
        rejoinCandidates = []
        showReversePrompt = false
        alternateCandidate = nil
        reversePromptDismissed = false

        if let last = processedRoute.points.last {
            endpointLocation = CLLocation(
                latitude: last.coordinate.latitude,
                longitude: last.coordinate.longitude)
        }
    }

    func anchorToLocation(_ location: CLLocation) {
        guard let route = route, route.points.count >= 2 else { return }

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
        rejoinCandidates = []
        showReversePrompt = false
        alternateCandidate = nil
        reversePromptDismissed = false
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

        // Compute rejoin candidates when off-route
        if isOffRoute {
            rejoinCandidates = computeRejoinCandidates(location: location, route: route)

            let nearestPoint = route.points[nearestIndex]
            bearingToRoute = RouteProcessor.bearing(
                from: location.coordinate,
                to: nearestPoint.coordinate)
            return nil
        } else {
            if !rejoinCandidates.isEmpty { rejoinCandidates = [] }
        }

        // Double-back detection: check for better alternate section
        if hasJoinedRoute, location.course >= 0 {
            evaluateAlternateSection(location: location, route: route, currentIndex: nearestIndex)
        }

        distanceAlongRoute = interpolateDistance(
            location: location,
            nearestIndex: nearestIndex,
            route: route)

        distanceRemaining = route.totalDistance - distanceAlongRoute
        currentBearing = route.points[nearestIndex].bearingToNext

        if let endpoint = endpointLocation {
            distanceToEndpoint = location.distance(from: endpoint)
        }

        if distanceToEndpoint <= endZoneOuter && distanceToEndpoint > endZoneInner {
            canCompleteRoute = true
        }

        if canCompleteRoute && distanceToEndpoint <= endZoneInner && distanceAlongRoute >= minDistanceForCompletion {
            isRouteComplete = true
            nextTurn = nil
            distanceToNextTurn = 0
            return nil
        }

        let previousTurn = nextTurn
        let previousDistance = distanceToNextTurn

        let newNextTurn = activeTurnPoints.first { $0.distanceFromStart > distanceAlongRoute - turnConfirmationBuffer }
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

    func resetCompletion() {
        canCompleteRoute = false
        isRouteComplete = false
    }

    func dismissReversePrompt() {
        showReversePrompt = false
        reversePromptDismissed = true
        alternateCandidate = nil
    }

    /// Change the turn mode mid-ride and recompute the next turn.
    func setTurnMode(_ mode: TurnMode) {
        turnMode = mode
        let turns = activeTurnPoints
        let newNext = turns.first { $0.distanceFromStart > distanceAlongRoute - turnConfirmationBuffer }
        nextTurn = newNext
        distanceToNextTurn = newNext.map { max(0, $0.distanceFromStart - distanceAlongRoute) } ?? 0
        lastPassedTurn = nil
        lastAlertedTurnIndex = nil
        lastAlertLevel = nil
        VoiceNavigator.shared.resetForRouteSwap()
    }

    /// Returns the turn immediately after `turn` if it's within `threshold` meters, using the active turn list.
    func nearbyFollowingTurn(after turn: TurnPoint, threshold: Double = 150) -> TurnPoint? {
        let turns = activeTurnPoints
        guard let idx = turns.firstIndex(where: { $0.index == turn.index }),
              idx + 1 < turns.count else { return nil }
        let next = turns[idx + 1]
        let gap = next.distanceFromStart - turn.distanceFromStart
        return gap <= threshold ? next : nil
    }

    func reverseRemainingRoute() {
        guard let route = route else { return }

        showReversePrompt = false
        alternateCandidate = nil

        let startIdx = max(0, currentSegmentIndex - 1)
        let remainingPoints = Array(route.points[startIdx...])
        guard remainingPoints.count >= 2 else { return }

        // Reverse the remaining points
        let reversed = remainingPoints.reversed()
        var newPoints: [ProcessedPoint] = []
        var cumDist = distanceAlongRoute

        let reversedArray = Array(reversed)
        for i in 0..<reversedArray.count {
            let pt = reversedArray[i]
            if i > 0 {
                let prevCoord = reversedArray[i - 1].coordinate
                let prevLoc = CLLocation(latitude: prevCoord.latitude, longitude: prevCoord.longitude)
                let curLoc = CLLocation(latitude: pt.coordinate.latitude, longitude: pt.coordinate.longitude)
                cumDist += curLoc.distance(from: prevLoc)
            }

            let bearing: Double
            if i < reversedArray.count - 1 {
                bearing = RouteProcessor.bearing(from: pt.coordinate, to: reversedArray[i + 1].coordinate)
            } else {
                bearing = newPoints.last?.bearingToNext ?? 0
            }

            newPoints.append(ProcessedPoint(
                coordinate: pt.coordinate,
                elevation: pt.elevation,
                distanceFromStart: cumDist,
                bearingToNext: bearing))
        }

        // Build new complete route: keep completed portion + reversed remainder
        let completedPoints = Array(route.points[0..<startIdx])
        let allPoints = completedPoints + newPoints
        let totalDist = allPoints.last?.distanceFromStart ?? 0

        // Recompute turns for reversed section
        var newTurns: [TurnPoint] = []
        // Keep turns that are already behind us (from the active turn list)
        for t in activeTurnPoints {
            if t.distanceFromStart < distanceAlongRoute - turnConfirmationBuffer {
                newTurns.append(t)
            }
        }

        // Detect turns in the new portion
        let newStart = completedPoints.count
        for i in (newStart + 1)..<(allPoints.count - 1) {
            let prevBearing = allPoints[i - 1].bearingToNext
            let nextBearing = allPoints[i].bearingToNext
            let angle = RouteProcessor.angleDelta(from: prevBearing, to: nextBearing)

            if abs(angle) >= RouteProcessor.turnAngleThreshold {
                let dist = allPoints[i].distanceFromStart
                let lastTurnDist = newTurns.last?.distanceFromStart ?? -RouteProcessor.minTurnSpacing
                if dist - lastTurnDist >= RouteProcessor.minTurnSpacing {
                    let direction = RouteProcessor.classifyTurn(angle)
                    newTurns.append(TurnPoint(
                        index: i,
                        angle: angle,
                        direction: direction,
                        distanceFromStart: dist,
                        coordinate: allPoints[i].coordinate))
                }
            }
        }

        // Compute bounding box
        let lats = allPoints.map { $0.coordinate.latitude }
        let lons = allPoints.map { $0.coordinate.longitude }

        let newRoute = ProcessedRoute(
            name: route.name,
            points: allPoints,
            waypointTurnPoints: [],
            calculatedTurnPoints: newTurns,
            totalDistance: totalDist,
            hasWaypoints: false,
            minLat: lats.min()!, maxLat: lats.max()!,
            minLon: lons.min()!, maxLon: lons.max()!)

        // Reload with new route, preserving position
        // Waypoints are invalidated by reversal — force calculated mode
        self.route = newRoute
        self.turnMode = .calculated
        currentSegmentIndex = min(startIdx, allPoints.count - 1)
        lastSearchIndex = currentSegmentIndex
        distanceRemaining = totalDist - distanceAlongRoute
        if let last = allPoints.last {
            endpointLocation = CLLocation(latitude: last.coordinate.latitude, longitude: last.coordinate.longitude)
        }

        // Reset turn tracking for the new route
        let newNextTurn = newTurns.first { $0.distanceFromStart > distanceAlongRoute - turnConfirmationBuffer }
        nextTurn = newNextTurn
        distanceToNextTurn = newNextTurn.map { max(0, $0.distanceFromStart - distanceAlongRoute) } ?? 0
        lastPassedTurn = nil
        lastAlertedTurnIndex = nil
        lastAlertLevel = nil
        reversePromptDismissed = true

        VoiceNavigator.shared.resetForRouteSwap()

        print("[Nav] Route reversed from segment \(startIdx). New total: \(Int(totalDist))m, \(newTurns.count) turns")
    }

    // Distance-based search window
    private let searchWindowMeters: Double = 500

    private func findNearest(
        location: CLLocation,
        in route: ProcessedRoute,
        searchCenter: Int
    ) -> (index: Int, distance: Double) {
        let currentRouteDist = route.points[max(0, min(searchCenter, route.points.count - 1))].distanceFromStart

        let minRouteDist = max(0, currentRouteDist - searchWindowMeters)
        let maxRouteDist: Double
        if hasJoinedRoute {
            maxRouteDist = min(route.totalDistance, currentRouteDist + searchWindowMeters)
        } else {
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

    // Evaluate whether the rider is consistently matching a different route section
    // (double-back detection / section skipping)
    private func evaluateAlternateSection(location: CLLocation, route: ProcessedRoute, currentIndex: Int) {
        let riderCourse = location.course
        guard riderCourse >= 0 else {
            alternateCandidate = nil
            return
        }

        guard currentIndex >= 0, currentIndex < route.points.count else {
            alternateCandidate = nil
            return
        }

        let currentRouteDist = route.points[currentIndex].distanceFromStart
        let currentBearingToNext = route.points[currentIndex].bearingToNext
        let currentHeadingDiff = abs(headingDelta(riderCourse, currentBearingToNext))

        // Only consider alternates when heading doesn't match current section well
        guard currentHeadingDiff > 90 else {
            alternateCandidate = nil
            showReversePrompt = false
            return
        }

        // Scan for geographically nearby points on distant route sections
        var bestAltIndex: Int?
        var bestAltScore = Double.greatestFiniteMagnitude

        for i in 0..<route.points.count {
            let point = route.points[i]
            let routeDistGap = abs(point.distanceFromStart - currentRouteDist)

            // Must be on a different section (>200m route-distance away)
            guard routeDistGap > 200 else { continue }

            let pointLoc = CLLocation(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude)
            let gpsDist = location.distance(from: pointLoc)

            // Must be geographically close
            guard gpsDist < offRouteThreshold else { continue }

            let headingDiff = abs(headingDelta(riderCourse, point.bearingToNext))

            // Score: GPS distance + heading mismatch penalty + backward penalty
            var score = gpsDist
            score += (headingDiff / 180.0) * 100

            // Penalty for jumping backward (prefer forward progress)
            if point.distanceFromStart < currentRouteDist {
                score += 30
            }

            if score < bestAltScore {
                bestAltScore = score
                bestAltIndex = i
            }
        }

        guard let altIdx = bestAltIndex else {
            // No good alternate found — if heading is still reversed, consider reverse prompt
            if !reversePromptDismissed, currentHeadingDiff > 140 {
                if let alt = alternateCandidate, alt.index == -1 {
                    let newCount = alt.sampleCount + 1
                    alternateCandidate = (index: -1, sampleCount: newCount)
                    if newCount >= alternateDwellThreshold {
                        showReversePrompt = true
                    }
                } else {
                    alternateCandidate = (index: -1, sampleCount: 1)
                }
            } else {
                alternateCandidate = nil
            }
            return
        }

        guard altIdx < route.points.count else {
            alternateCandidate = nil
            return
        }

        let altHeadingDiff = abs(headingDelta(riderCourse, route.points[altIdx].bearingToNext))

        // The alternate must have significantly better heading alignment
        guard altHeadingDiff < 60 && altHeadingDiff < currentHeadingDiff - 40 else {
            alternateCandidate = nil
            return
        }

        // Track sustained match
        if let existing = alternateCandidate,
           existing.index >= 0,
           existing.index < route.points.count,
           abs(route.points[existing.index].distanceFromStart - route.points[altIdx].distanceFromStart) < 200 {
            // Same section — increment count
            let newCount = existing.sampleCount + 1
            alternateCandidate = (index: altIdx, sampleCount: newCount)

            if newCount >= alternateDwellThreshold {
                // Jump to alternate section
                print("[Nav] Jumping to alternate section at index \(altIdx) "
                    + "(dist=\(Int(route.points[altIdx].distanceFromStart))m) "
                    + "after \(newCount) samples")
                lastSearchIndex = altIdx
                currentSegmentIndex = altIdx
                distanceAlongRoute = route.points[altIdx].distanceFromStart
                alternateCandidate = nil
                showReversePrompt = false
            }
        } else {
            // New candidate section — start fresh
            alternateCandidate = (index: altIdx, sampleCount: 1)
        }
    }

    // Compute clustered rejoin candidates when off-route
    private func computeRejoinCandidates(location: CLLocation, route: ProcessedRoute) -> [RejoinCandidate] {
        let maxRejoinScanDistance: Double = 500

        // Find all points within scan distance
        struct NearbyPoint {
            let index: Int
            let gpsDist: Double
            let routeDist: Double
            let coord: CLLocationCoordinate2D
        }

        var nearby: [NearbyPoint] = []
        for i in 0..<route.points.count {
            let point = route.points[i]
            let pointLoc = CLLocation(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude)
            let dist = location.distance(from: pointLoc)
            if dist < maxRejoinScanDistance {
                nearby.append(NearbyPoint(
                    index: i,
                    gpsDist: dist,
                    routeDist: point.distanceFromStart,
                    coord: point.coordinate))
            }
        }

        guard !nearby.isEmpty else { return [] }

        // Sort by route distance for clustering
        let sorted = nearby.sorted { $0.routeDist < $1.routeDist }

        // Cluster: new cluster when route-distance gap > 200m
        var clusters: [[NearbyPoint]] = []
        var currentCluster: [NearbyPoint] = [sorted[0]]

        for i in 1..<sorted.count {
            if sorted[i].routeDist - sorted[i - 1].routeDist > 200 {
                clusters.append(currentCluster)
                currentCluster = [sorted[i]]
            } else {
                currentCluster.append(sorted[i])
            }
        }
        clusters.append(currentCluster)

        // Take closest point from each cluster
        var candidates: [RejoinCandidate] = clusters.compactMap { cluster in
            guard let closest = cluster.min(by: { $0.gpsDist < $1.gpsDist }) else { return nil }
            return RejoinCandidate(
                segmentIndex: closest.index,
                coordinate: closest.coord,
                distance: closest.gpsDist)
        }

        // Sort by GPS distance, limit to 3
        candidates.sort { $0.distance < $1.distance }
        if candidates.count > 3 {
            candidates = Array(candidates.prefix(3))
        }

        return candidates
    }

    private func headingDelta(_ a: Double, _ b: Double) -> Double {
        var delta = b - a
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }

    private func findMissedTurn(at location: CLLocation, in route: ProcessedRoute) -> TurnPoint? {
        if let turn = lastPassedTurn {
            let turnLoc = CLLocation(latitude: turn.coordinate.latitude, longitude: turn.coordinate.longitude)
            if location.distance(from: turnLoc) < missedTurnProximity {
                return turn
            }
        }

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
