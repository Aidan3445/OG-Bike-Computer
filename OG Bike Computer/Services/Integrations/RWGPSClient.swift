//
//  RWGPSClient.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "RWGPS")

class RWGPSClient: ServiceClient {
    let serviceID: IntegrationServiceID = .rideWithGPS
    private let baseURL = "https://ridewithgps.com/api/v1"

    func fetchRoutes(page: Int) async throws -> [ServiceRoute] {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)
        let offset = page * 20

        var request = URLRequest(url: URL(string: "\(baseURL)/routes.json?offset=\(offset)&limit=20")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let routeList = try JSONDecoder().decode(RWGPSRouteListResponse.self, from: data)
        return routeList.results.map { route in
            ServiceRoute(
                id: "\(route.id)",
                name: route.name ?? "Unnamed Route",
                distance: route.distance ?? 0,
                elevationGain: route.elevation_gain ?? 0,
                createdAt: route.created_at ?? Date()
            )
        }
    }

    func downloadRoute(id: String) async throws -> Route {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)

        var request = URLRequest(url: URL(string: "\(baseURL)/routes/\(id).json")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let rwgpsRoute = try JSONDecoder().decode(RWGPSRouteDetail.self, from: data)
        return convertToRoute(rwgpsRoute, remoteID: id)
    }

    private func convertToRoute(_ rwgps: RWGPSRouteDetail, remoteID: String) -> Route {
        let trackPoints = (rwgps.track_points ?? []).map { pt in
            TrackPoint(lat: pt.y, lon: pt.x, elevation: pt.e)
        }

        let waypoints = (rwgps.course_points ?? []).compactMap { cp -> Waypoint? in
            guard let name = cp.t else { return nil }
            return Waypoint(
                lat: cp.y,
                lon: cp.x,
                name: name,
                description: cp.n
            )
        }

        return Route(
            name: rwgps.name ?? "RWGPS Route",
            points: trackPoints,
            waypoints: waypoints.isEmpty ? nil : waypoints,
            source: RouteSource(service: .rideWithGPS, remoteID: remoteID)
        )
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200...299: return
        case 401: throw ServiceError.notAuthenticated
        case 429: throw ServiceError.rateLimited
        default: throw ServiceError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - RWGPS API Response Models

struct RWGPSRouteListResponse: Codable {
    let results: [RWGPSRouteListItem]
}

struct RWGPSRouteListItem: Codable {
    let id: Int
    let name: String?
    let distance: Double?       // meters
    let elevation_gain: Double? // meters
    let created_at: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, elevation_gain, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)
        distance = try container.decodeIfPresent(Double.self, forKey: .distance)
        elevation_gain = try container.decodeIfPresent(Double.self, forKey: .elevation_gain)

        if let dateString = try container.decodeIfPresent(String.self, forKey: .created_at) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            created_at = formatter.date(from: dateString) ?? {
                // Fallback without fractional seconds
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: dateString)
            }()
        } else {
            created_at = nil
        }
    }
}

struct RWGPSRouteDetail: Codable {
    let name: String?
    let track_points: [RWGPSTrackPoint]?
    let course_points: [RWGPSCoursePoint]?
}

struct RWGPSTrackPoint: Codable {
    let x: Double  // longitude
    let y: Double  // latitude
    let e: Double? // elevation
}

struct RWGPSCoursePoint: Codable {
    let x: Double  // longitude
    let y: Double  // latitude
    let t: String? // type (turn direction)
    let n: String? // note/description
}
