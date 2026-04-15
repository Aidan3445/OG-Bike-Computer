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

        var request = URLRequest(url: URL(string: "\(baseURL)/athletes/\(athleteID)/routes?page=\(page)&per_page=20")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let routes = try JSONDecoder().decode([StravaRoute].self, from: data)
        logger.debug("Fetched \(routes.count) routes (page \(page))")

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

    func extractRouteID(from url: String) -> String? {
        let pattern = #"strava\.com/routes/(\d+)"#
        if let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) {
            let range = NSRange(url.startIndex..<url.endIndex, in: url)
            if let match = regex.firstMatch(in: url, options: [], range: range),
               let idRange = Range(match.range(at: 1), in: url) {
                return String(url[idRange])
            }
        }
        return nil
    }

    func fetchRouteMetadata(id: String) async throws -> ServiceRoute {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        var request = URLRequest(url: URL(string: "\(baseURL)/routes/\(id)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let route = try JSONDecoder().decode(StravaRoute.self, from: data)
        return ServiceRoute(
            id: "\(route.id)",
            name: route.name,
            distance: route.distance,
            elevationGain: route.elevation_gain,
            createdAt: route.created_at ?? Date()
        )
    }

    /// Downloads a route as GPX and parses it using the existing GPX parser.
    /// Strava route waypoints are POIs (not turn cues), so GPX export is the
    /// best source — our parser extracts any `<wpt>` turn directions present.
    func downloadRoute(id: String) async throws -> Route {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        var request = URLRequest(url: URL(string: "\(baseURL)/routes/\(id)/export_gpx")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let parser = GPXParser()
        let routes = parser.parse(data: data)
        guard let parsed = routes.first else {
            throw ServiceError.noData
        }

        logger.info("Imported '\(parsed.name)': \(parsed.points.count) pts, \(parsed.waypoints?.count ?? 0) cues")

        return Route(
            name: parsed.name,
            points: parsed.points,
            waypoints: parsed.waypoints,
            source: RouteSource(service: .strava, remoteID: id)
        )
    }

    // MARK: - Upload

    /// POST the GPX file to Strava. Returns the uploadId and a partial record (no activityID yet).
    func startUpload(gpxData: Data, name: String, externalId: String) async throws -> (uploadId: Int, record: ServiceUploadRecord) {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        let boundary = UUID().uuidString
        var request = URLRequest(url: URL(string: "\(baseURL)/uploads")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()
        body.appendMultipart(name: "data_type", value: "gpx", boundary: boundary)
        body.appendMultipart(name: "name", value: name, boundary: boundary)
        body.appendMultipart(name: "external_id", value: externalId, boundary: boundary)
        body.appendMultipart(name: "description", value: "Recorded with Computa for Apple Watch", boundary: boundary)

        // GPX file attachment
        body.append("--\(boundary)\r\n".data(using: .utf8)!)
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"\(name).gpx\"\r\n".data(using: .utf8)!)
        body.append("Content-Type: application/gpx+xml\r\n\r\n".data(using: .utf8)!)
        body.append(gpxData)
        body.append("\r\n--\(boundary)--\r\n".data(using: .utf8)!)

        request.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let uploadResponse = try JSONDecoder().decode(StravaUploadResponse.self, from: data)
        logger.info("Upload started, id=\(uploadResponse.id)")

        let record = ServiceUploadRecord(
            service: .strava,
            uploadedAt: Date(),
            webURL: nil,
            uploadId: uploadResponse.id
        )
        return (uploadResponse.id, record)
    }

    /// Poll Strava until the upload is processed and an activityID is available.
    func pollUpload(uploadID: Int, attempts: Int = 0) async throws -> (activityID: Int, webURL: String) {
        if attempts >= 15 {
            throw ServiceError.uploadFailed("Upload processing timed out")
        }

        try await Task.sleep(nanoseconds: UInt64(min(2 + attempts * 2, 10)) * 1_000_000_000)

        let token = try await OAuthManager.shared.validToken(for: .strava)

        var request = URLRequest(url: URL(string: "\(baseURL)/uploads/\(uploadID)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        let status = try JSONDecoder().decode(StravaUploadStatus.self, from: data)

        if let activityID = status.activity_id {
            return (activityID, "https://www.strava.com/activities/\(activityID)")
        }

        if let error = status.error {
            if error.lowercased().contains("duplicate") {
                // Strava sometimes includes activity_id even on duplicate
                if let activityID = status.activity_id {
                    return (activityID, "https://www.strava.com/activities/\(activityID)")
                }
                throw ServiceError.uploadFailed("Activity already exists on Strava (duplicate)")
            }
            throw ServiceError.uploadFailed(error)
        }

        return try await pollUpload(uploadID: uploadID, attempts: attempts + 1)
    }

    /// Single status check for an existing upload (non-recursive).
    func checkUploadStatus(uploadID: Int) async throws -> StravaUploadStatus {
        let token = try await OAuthManager.shared.validToken(for: .strava)

        var request = URLRequest(url: URL(string: "\(baseURL)/uploads/\(uploadID)")!)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        try validateResponse(response)

        return try JSONDecoder().decode(StravaUploadStatus.self, from: data)
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
    let distance: Double        // meters
    let elevation_gain: Double  // meters
    let created_at: Date?
    let description: String?
    let starred: Bool?
    let sub_type: Int?          // 1=road, 2=mtb, 3=cx, 4=trail, 5=mixed
    let map: StravaMap?

    enum CodingKeys: String, CodingKey {
        case id, name, distance, elevation_gain, created_at, description, starred, sub_type, map
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        distance = try container.decode(Double.self, forKey: .distance)
        elevation_gain = try container.decode(Double.self, forKey: .elevation_gain)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        starred = try container.decodeIfPresent(Bool.self, forKey: .starred)
        sub_type = try container.decodeIfPresent(Int.self, forKey: .sub_type)
        map = try container.decodeIfPresent(StravaMap.self, forKey: .map)

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

struct StravaMap: Codable {
    let id: String?
    let polyline: String?
    let summary_polyline: String?
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
