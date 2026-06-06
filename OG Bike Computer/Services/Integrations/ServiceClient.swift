//
//  ServiceClient.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation

protocol ServiceClient {
    var serviceID: IntegrationServiceID { get }

    /// Fetch a paginated list of the user's routes
    func fetchRoutes(page: Int) async throws -> [ServiceRoute]

    /// Download a full route by its remote ID, ready to save locally
    func downloadRoute(id: String) async throws -> Route
}

protocol UploadableServiceClient: ServiceClient {
    /// POST the ride file and return the upload ID + partial record (before polling)
    func startUpload(gpxData: Data, name: String, externalId: String) async throws -> (uploadId: Int, record: ServiceUploadRecord)

    /// Poll until the upload is processed and return the activity ID + web URL
    func pollUpload(uploadID: Int, attempts: Int) async throws -> (activityID: Int, webURL: String)
}

enum ServiceError: LocalizedError {
    case notAuthenticated
    case tokenExpired
    case rateLimited
    case serverError(Int)
    case networkError(Error)
    case decodingError(Error)
    case uploadFailed(String)
    /// Strava reports the activity already exists. Terminal — no point retrying.
    case duplicate
    case noData
    case invalidURL

    var errorDescription: String? {
        switch self {
        case .notAuthenticated: return "Not authenticated. Please reconnect your account."
        case .tokenExpired: return "Session expired. Please reconnect your account."
        case .rateLimited: return "Rate limit exceeded. Please try again later."
        case .serverError(let code): return "Server error (\(code)). Please try again."
        case .networkError(let error): return "Network error: \(error.localizedDescription)"
        case .decodingError: return "Failed to parse response from server."
        case .uploadFailed(let msg): return "Upload failed: \(msg)"
        case .duplicate: return "Activity already exists on Strava."
        case .noData: return "No data received from server."
        case .invalidURL: return "Unable to parse URL. Please check and try again."
        }
    }
}
