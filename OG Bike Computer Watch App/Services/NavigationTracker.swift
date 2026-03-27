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

    // Section jump confirmation: tracks sustained match to a different route section
    private var jumpCandidate: (segmentIndex: Int, sampleCount: Int)?
    private let jumpConfirmationThreshold = 4 // consecutive samples before jumping (~4s at 1Hz)

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
        jumpCandidate = nil

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
        jumpCandidate = nil
    }

    func update(location: CLLocation, riderDistance: Double = 0) -> TurnAlert? {
        guard let route = route, route.points.count >= 2 else { return nil }

        let (nearestIndex, nearestDistance) = findNearest(
            location: location,
            in: route
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

    private let candidateRadius: Double = 200
    private let clusterGap: Double = 200

    private func findNearest(
        location: CLLocation,
        in route: ProcessedRoute
    ) -> (index: Int, distance: Double) {
        let riderCourse = location.course
        let currentRouteDist = route.points[max(0, min(currentSegmentIndex, route.points.count - 1))].distanceFromStart

        // Phase 1: Gather all route points within candidateRadius
        struct Candidate {
            let index: Int
            let gpsDist: Double
        }

        var candidates: [Candidate] = []
        var globalBestIndex = 0
        var globalBestDist = Double.greatestFiniteMagnitude

        for i in 0..<route.points.count {
            let point = route.points[i]
            let pointLoc = CLLocation(
                latitude: point.coordinate.latitude,
                longitude: point.coordinate.longitude)
            let dist = location.distance(from: pointLoc)

            if dist < globalBestDist {
                globalBestDist = dist
                globalBestIndex = i
            }

            if dist <= candidateRadius {
                candidates.append(Candidate(index: i, gpsDist: dist))
            }
        }

        // No candidates within radius — return global nearest
        if candidates.isEmpty {
            if !hasJoinedRoute && globalBestDist <= offRouteThreshold {
                hasJoinedRoute = true
            }
            jumpCandidate = nil
            return (globalBestIndex, globalBestDist)
        }

        // Phase 2: Cluster candidates by route distance
        candidates.sort { route.points[$0.index].distanceFromStart < route.points[$1.index].distanceFromStart }

        var clusters: [[Candidate]] = []
        var currentCluster: [Candidate] = [candidates[0]]

        for i in 1..<candidates.count {
            let prevRouteDist = route.points[currentCluster.last!.index].distanceFromStart
            let thisRouteDist = route.points[candidates[i].index].distanceFromStart
            if thisRouteDist - prevRouteDist > clusterGap {
                clusters.append(currentCluster)
                currentCluster = [candidates[i]]
            } else {
                currentCluster.append(candidates[i])
            }
        }
        clusters.append(currentCluster)

        // Phase 3: Score each cluster's best representative
        struct ScoredCluster {
            let index: Int
            let gpsDist: Double
            let score: Double
            let routeDist: Double
        }

        var scored: [ScoredCluster] = []

        for cluster in clusters {
            let best = cluster.min(by: { $0.gpsDist < $1.gpsDist })!
            let point = route.points[best.index]

            var score = 0.0

            // GPS proximity (0-100): dominant signal
            score += (best.gpsDist / candidateRadius) * 100.0

            // Heading alignment (0-50): disambiguates double-backs
            if riderCourse >= 0 {
                let bearingDiff = abs(headingDelta(riderCourse, point.bearingToNext))
                score += (bearingDiff / 180.0) * 50.0
            }

            // Route continuity (0-40): prevents oscillation
            let routeDistDelta = abs(point.distanceFromStart - currentRouteDist)
            score += min(routeDistDelta * 0.02, 40.0)

            // Forward progress bias (0-20): mild penalty for large backward jumps
            if hasJoinedRoute {
                if point.distanceFromStart < currentRouteDist - 500 {
                    score += 20.0
                } else if point.distanceFromStart < currentRouteDist - 50 {
                    score += 10.0
                }
            }

            scored.append(ScoredCluster(
                index: best.index,
                gpsDist: best.gpsDist,
                score: score,
                routeDist: point.distanceFromStart))
        }

        scored.sort { $0.score < $1.score }
        let winner = scored[0]

        // Pre-join: accept immediately
        if !hasJoinedRoute {
            if winner.gpsDist <= offRouteThreshold {
                hasJoinedRoute = true
            }
            jumpCandidate = nil
            return (winner.index, winner.gpsDist)
        }

        // Phase 4: Section jump confirmation
        let isSameSection = abs(winner.routeDist - currentRouteDist) < clusterGap

        if isSameSection {
            jumpCandidate = nil
            return (winner.index, winner.gpsDist)
        }

        // Different section — require confirmation
        if let existing = jumpCandidate {
            let existingRouteDist = route.points[existing.segmentIndex].distanceFromStart
            if abs(existingRouteDist - winner.routeDist) < clusterGap {
                // Same target section as previous sample
                let newCount = existing.sampleCount + 1
                if newCount >= jumpConfirmationThreshold {
                    jumpCandidate = nil
                    print("[Nav] Section jump to index \(winner.index) "
                        + "(dist=\(Int(winner.routeDist))m) "
                        + "confirmed after \(newCount) samples")
                    return (winner.index, winner.gpsDist)
                } else {
                    jumpCandidate = (segmentIndex: winner.index, sampleCount: newCount)
                }
            } else {
                // Different target — reset
                jumpCandidate = (segmentIndex: winner.index, sampleCount: 1)
            }
        } else {
            jumpCandidate = (segmentIndex: winner.index, sampleCount: 1)
        }

        // While confirming, stay on current section if possible
        if let fallback = scored.first(where: { abs($0.routeDist - currentRouteDist) < clusterGap }) {
            return (fallback.index, fallback.gpsDist)
        }

        // No current-section cluster (drifted away) — accept jump immediately
        jumpCandidate = nil
        return (winner.index, winner.gpsDist)
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
