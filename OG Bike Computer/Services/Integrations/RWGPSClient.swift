//
//  RWGPSClient.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "RWGPS")

struct RWGPSRouteFilter {
    var name: String = ""
    var distanceMin: Int?  // meters
    var distanceMax: Int?  // meters

    var isEmpty: Bool {
        name.isEmpty && distanceMin == nil && distanceMax == nil
    }
}

class RWGPSClient: ServiceClient {
    let serviceID: IntegrationServiceID = .rideWithGPS
    private let baseURL = "https://ridewithgps.com/api/v1"

    var filter = RWGPSRouteFilter()

    func fetchRoutes(page: Int) async throws -> [ServiceRoute] {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)

        var components = URLComponents(string: "\(baseURL)/routes.json")!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "page", value: "\(page)"),
            URLQueryItem(name: "page_size", value: "20"),
        ]

        if !filter.name.isEmpty {
            queryItems.append(URLQueryItem(name: "name", value: filter.name))
        }
        if let distMin = filter.distanceMin {
            queryItems.append(URLQueryItem(name: "distance_min", value: "\(distMin)"))
        }
        if let distMax = filter.distanceMax {
            queryItems.append(URLQueryItem(name: "distance_max", value: "\(distMax)"))
        }

        components.queryItems = queryItems

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(RWGPSRouteListResponse.self, from: data)
        logger.debug("Fetched \(decoded.routes.count) routes (page \(page))")

        return decoded.routes.map { route in
            ServiceRoute(
                id: "\(route.id)",
                name: route.name ?? "Unnamed Route",
                distance: route.distance ?? 0,
                elevationGain: route.elevation_gain ?? 0,
                createdAt: route.created_at ?? Date()
            )
        }
    }

    func fetchCollections() async throws -> [RWGPSCollection] {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)
        let components = URLComponents(string: "\(baseURL)/collections.json")!

        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(RWGPSCollectionListResponse.self, from: data)
        logger.debug("Fetched \(decoded.collections.count) collections")


        return decoded.collections.map { col in
            RWGPSCollection(
                id: "\(col.id)",
                name: col.name?.localizedCapitalized ?? "Unnamed Collection",
                createdAt: col.created_at ?? Date(),
                routes: nil
            )
        }
    }

    func fetchRoutesForCollection(id: String) async throws -> [ServiceRoute] {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)

        var request = URLRequest(url: URL(string: "\(baseURL)/collections/\(id).json")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let decoded = try JSONDecoder().decode(RWGPSCollectionDetailResponse.self, from: data)
        let routeCount = decoded.collection.routes?.count ?? 0

        logger.debug("Fetched \(routeCount) routes for collection \(id)")

        if routeCount == 0 {
            return []
        }

        return decoded.collection.routes!.map { route in
            ServiceRoute(
                id: "\(route.id)",
                name: route.name ?? "Unnamed Route",
                distance: route.distance ?? 0,
                elevationGain: route.elevation_gain ?? 0,
                createdAt: route.created_at ?? Date()
            )
        }
    }

    func fetchByURL(url: String) async throws -> Route {
        guard let id = extractRouteID(from: url) else {
            throw ServiceError.invalidURL
        }
        return try await downloadRoute(id: id)
    }

    func extractRouteID(from url: String) -> String? {
        // RWGPS route URLs look like: https://ridewithgps.com/routes/12345678
        // there may be query parameters or fragments after the ID, so we just want to extract the number after /routes/
        let pattern = #"ridewithgps\.com/routes/(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: url) {
                return String(url[idRange])
            }
        }
        return nil
    }

    func downloadRoute(id: String) async throws -> Route {
        let token = try await OAuthManager.shared.validToken(for: .rideWithGPS)

        var request = URLRequest(url: URL(string: "\(baseURL)/routes/\(id).json")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let wrapper: RWGPSRouteDetailWrapper
        do {
            wrapper = try JSONDecoder().decode(RWGPSRouteDetailWrapper.self, from: data)
        } catch {
            logger.error("Failed to decode route \(id): \(error)")
            throw ServiceError.decodingError(error)
        }

        return convertToRoute(wrapper.route, remoteID: id)
    }

    private func convertToRoute(_ rwgps: RWGPSRouteDetail, remoteID: String) -> Route {
        let trackPoints = (rwgps.track_points ?? []).map { pt in
            TrackPoint(lat: pt.y, lon: pt.x, elevation: pt.e)
        }

        let waypoints = (rwgps.course_points ?? []).compactMap { cp -> Waypoint? in
            guard let type = cp.t else { return nil }
            return Waypoint(
                lat: cp.y,
                lon: cp.x,
                name: type,
                description: cp.n
            )
        }

        logger.info("Imported '\(rwgps.name ?? "unnamed")': \(trackPoints.count) pts, \(waypoints.count) cues")

        return Route(
            name: rwgps.name ?? "Unnamed Route",
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
    let routes: [RWGPSRouteListItem]
    let meta: RWGPSMeta?
}

struct RWGPSMeta: Codable {
    let pagination: RWGPSPagination?
}

struct RWGPSPagination: Codable {
    let record_count: Int?
    let page_count: Int?
    let page_size: Int?
    let next_page_url: String?
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
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: dateString)
            }()
        } else {
            created_at = nil
        }
    }
}

/// Wrapper: API returns `{ "route": { ... } }`
struct RWGPSRouteDetailWrapper: Codable {
    let route: RWGPSRouteDetail
}

struct RWGPSRouteDetail: Codable {
    let id: Int?
    let name: String?
    let description: String?
    let distance: Double?
    let elevation_gain: Double?
    let elevation_loss: Double?
    let track_points: [RWGPSTrackPoint]?
    let course_points: [RWGPSCoursePoint]?
    let points_of_interest: [RWGPSPointOfInterest]?
}

/// Route track point — per RWGPS API docs
struct RWGPSTrackPoint: Codable {
    let x: Double   // longitude (degrees)
    let y: Double   // latitude (degrees)
    let d: Double?  // distance from start (meters)
    let e: Double?  // elevation (meters)
    let S: Int?     // surface type
    let R: Int?     // highway tag
}

/// Route course point (cue) — per RWGPS API docs
struct RWGPSCoursePoint: Codable {
    let x: Double   // longitude (degrees)
    let y: Double   // latitude (degrees)
    let d: Double?  // distance from start (meters)
    let i: Int?     // cue track index into track_points
    let t: String?  // cue type ("Left", "Right", "Straight", etc.)
    let n: String?  // cue text ("Turn left onto Main St")
    let userEdited: Bool?

    enum CodingKeys: String, CodingKey {
        case x, y, d, i, t, n
        case userEdited = "_e"
    }
}

struct RWGPSPointOfInterest: Codable {
    let id: Int?
    let name: String?
    let description: String?
    let lat: Double?
    let lng: Double?
    let type_name: String?
}

/// Collections API response models
struct RWGPSCollectionListResponse: Codable {
    let collections: [RWGPSCollectionListItem]
    let meta: RWGPSMeta?
}

struct RWGPSCollectionListItem: Codable {
    let id: Int
    let name: String?
    let created_at: Date?
    let routes: [RWGPSRouteListItem]?

    enum CodingKeys: String, CodingKey {
        case id, name, created_at, routes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decodeIfPresent(String.self, forKey: .name)

        if let dateString = try container.decodeIfPresent(String.self, forKey: .created_at) {
            let formatter = ISO8601DateFormatter()
            formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            created_at = formatter.date(from: dateString) ?? {
                let f2 = ISO8601DateFormatter()
                f2.formatOptions = [.withInternetDateTime]
                return f2.date(from: dateString)
            }()
        } else {
            created_at = nil
        }

        if let routesArray = try? container.decodeIfPresent([RWGPSRouteListItem].self, forKey: .routes) {
            routes = routesArray
        } else {
            routes = nil
        }
    }
}

struct RWGPSCollectionDetailResponse: Codable {
    let collection: RWGPSCollectionListItem
}

struct RWGPSCollection: Identifiable {
    let id: String
    let name: String
    let createdAt: Date
    let routes: [ServiceRoute]?
}
