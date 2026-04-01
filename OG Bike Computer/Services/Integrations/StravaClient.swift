//
//  StravaClient.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import os

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "Strava")

class StravaClient: ServiceClient, UploadableServiceClient {
    let serviceID: IntegrationServiceID = .strava
    private let baseURL = "https://www.strava.com/api/v3"

    // MARK: - Routes

    func fetchRoutes(page: Int) async throws -> [ServiceRoute] {
        let token = try await OAuthManager.shared.validToken(for: .strava)
        guard let tokens = KeychainHelper.loadTokens(for: .strava),
              let athleteID = tokens.athleteID else {
            throw ServiceError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "\(baseURL)/athletes/\(athleteID)/routes?page=\(page + 1)&per_page=20")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let routes = try JSONDecoder().decode([StravaRoute].self, from: data)
        return routes.map { route in
            ServiceRoute(
                id: "\(route.id)",
                name: route.name,
                distance: route.distance,
                elevationGain: route.elevation_gain,
                createdAt: route.created_at ?? Date()
            )
        }
    }

    func downloadRoute(id: String) async throws -> Route {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        var request = URLRequest(url: URL(string: "\(baseURL)/routes/\(id)/export_gpx")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let parser = GPXParser()
        let routes = parser.parse(data: data)
        guard var route = routes.first else {
            throw ServiceError.noData
        }

        // Re-create with source metadata
        route = Route(
            name: route.name,
            points: route.points,
            waypoints: route.waypoints,
            source: RouteSource(service: .strava, remoteID: id)
        )
        return route
    }

    // MARK: - Upload

    func uploadRide(gpxData: Data, name: String) async throws -> ServiceUploadRecord {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        // data_type field
        body.appendMultipart(name: "data_type", value: "gpx", boundary: boundary)

        // name field
        body.appendMultipart(name: "name", value: name, boundary: boundary)

        // file field
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name).gpx\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(gpxData)
        body.append("\r\n".data(using: .utf8)!)

        // Close boundary
        body.append("--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let uploadResponse = try JSONDecoder().decode(StravaUploadResponse.self, from: data)
        logger.info("[Strava] Upload started, id: \(uploadResponse.id)")

        // Poll for completion
        let activityID = try await pollUpload(uploadID: uploadResponse.id, token: token)

        return ServiceUploadRecord(
            service: .strava,
            remoteID: "\(activityID)",
            uploadedAt: Date(),
            webURL: "https://www.strava.com/activities/\(activityID)"
        )
    }

    private func pollUpload(uploadID: Int, token: String, attempts: Int = 0) async throws -> Int {
        if attempts >= 15 {
            throw ServiceError.uploadFailed("Upload processing timed out")
        }

        // Wait before polling (exponential backoff: 2, 4, 6 seconds)
        try await Task.sleep(nanoseconds: UInt64(min(2 + attempts * 2, 10)) * 1_000_000_000)

        var request = URLRequest(url: URL(string: "\(baseURL)/uploads/\(uploadID)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let status = try JSONDecoder().decode(StravaUploadStatus.self, from: data)

        if let activityID = status.activity_id {
            return activityID
        }

        if let error = status.error {
            // "duplicate" errors mean it already exists — still a success from our perspective
            if error.lowercased().contains("duplicate") {
                logger.info("[Strava] Upload was a duplicate")
                // Return the upload ID as a fallback identifier
                throw ServiceError.uploadFailed("Activity already exists on Strava (duplicate)")
            }
            throw ServiceError.uploadFailed(error)
        }

        return try await pollUpload(uploadID: uploadID, token: token, attempts: attempts + 1)
    }

    // MARK: - Helpers

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else { return }
        switch httpResponse.statusCode {
        case 200...299: return
        case 401: throw ServiceError.tokenExpired
        case 429: throw ServiceError.rateLimited
        default: throw ServiceError.serverError(httpResponse.statusCode)
        }
    }
}

// MARK: - Multipart Helper

private extension Data {
    mutating func appendMultipart(name: String, value: String, boundary: String) {
        append("--\(boundary)\r\n".data(using: .utf8)!)
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n".data(using: .utf8)!)
        append("\(value)\r\n".data(using: .utf8)!)
    }
}

// MARK: - Strava API Models

struct StravaRoute: Codable {
    let id: Int
    let name: String
    let distance: Double
    let elevation_gain: Double
    let created_at: Date?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, elevation_gain, created_at
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        distance = try container.decode(Double.self, forKey: .distance)
        elevation_gain = try container.decode(Double.self, forKey: .elevation_gain)

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

struct StravaUploadResponse: Codable {
    let id: Int
    let status: String?
}

struct StravaUploadStatus: Codable {
    let id: Int
    let activity_id: Int?
    let status: String?
    let error: String?
}
