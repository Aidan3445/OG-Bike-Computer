//
//  StravaClient+Elevation.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 10/29/26.
//

#if DEBUG
import Foundation

/// Read-only calls for the elevation comparison in Diagnostics.
extension StravaClient {
    struct ActivityElevation: Codable {
        let id: Int
        let totalElevationGain: Double
        let elevHigh: Double?
        let elevLow: Double?
        let distance: Double
        let deviceName: String?

        enum CodingKeys: String, CodingKey {
            case id, distance
            case totalElevationGain = "total_elevation_gain"
            case elevHigh = "elev_high"
            case elevLow = "elev_low"
            case deviceName = "device_name"
        }
    }

    struct AltitudeStreams {
        let time: [Double]
        let distance: [Double]
        let altitude: [Double]
    }

    func fetchActivityElevation(id: String) async throws -> ActivityElevation {
        let data = try await get("/activities/\(id)")
        return try JSONDecoder().decode(ActivityElevation.self, from: data)
    }

    /// The altitude Strava used for the activity, with time and distance to line it up.
    func fetchAltitudeStreams(id: String) async throws -> AltitudeStreams {
        let data = try await get("/activities/\(id)/streams?keys=time,distance,altitude&key_by_type=true")
        struct Stream: Decodable { let data: [Double] }
        let streams = try JSONDecoder().decode([String: Stream].self, from: data)
        return AltitudeStreams(
            time: streams["time"]?.data ?? [],
            distance: streams["distance"]?.data ?? [],
            altitude: streams["altitude"]?.data ?? [])
    }

    private func get(_ path: String) async throws -> Data {
        let token = try await OAuthManager.shared.validToken(for: .strava)
        guard let url = URL(string: "https://www.strava.com/api/v3\(path)") else { throw ServiceError.invalidURL }
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        if let http = response as? HTTPURLResponse {
            switch http.statusCode {
            case 200...299: break
            case 401: throw ServiceError.tokenExpired
            case 429: throw ServiceError.rateLimited
            default: throw ServiceError.serverError(http.statusCode)
            }
        }
        return data
    }
}
#endif
