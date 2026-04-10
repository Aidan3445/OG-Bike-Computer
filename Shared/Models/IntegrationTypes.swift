//
//  IntegrationTypes.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation

// MARK: - Service Identifiers

enum IntegrationServiceID: String, Codable, CaseIterable, Identifiable {
    case rideWithGPS
    case strava
    case fitness

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rideWithGPS: return "Ride With GPS"
        case .strava: return "Strava"
        case .fitness: return "Apple Fitness"
        }
    }

    var iconAsset: String {
        switch self {
        case .rideWithGPS: return "RWGPSIcon"
        case .strava: return "StravaIcon"
        case .fitness: return "FitnessIcon"
        }
    }

    var brandColor: String {
        switch self {
        case .rideWithGPS: return "rwgpsOrange"
        case .strava: return "stravaOrange"
        case .fitness: return "fitnessPink"
        }
    }

    /// Services that use OAuth connections (shown in integration settings)
    static var oauthServices: [IntegrationServiceID] {
        [.rideWithGPS, .strava]
    }
}

// MARK: - Route Source

struct RouteSource: Codable, Equatable {
    let service: IntegrationServiceID
    let remoteID: String
}

// MARK: - Upload Record

struct ServiceUploadRecord: Codable, Equatable, Identifiable {
    var id: String {
        if let remoteID { return "\(service.rawValue)-\(remoteID)" }
        return "\(service.rawValue)-upload-\(uploadId ?? 0)"
    }
    let service: IntegrationServiceID
    var remoteID: String?
    var uploadedAt: Date
    var webURL: String?
    let uploadId: Int?

    /// Upload is complete when we have the remote activity ID
    var isComplete: Bool { remoteID != nil }

    init(service: IntegrationServiceID, remoteID: String? = nil, uploadedAt: Date, webURL: String?, uploadId: Int? = nil) {
        self.service = service
        self.remoteID = remoteID
        self.uploadedAt = uploadedAt
        self.webURL = webURL
        self.uploadId = uploadId
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        service = try c.decode(IntegrationServiceID.self, forKey: .service)
        remoteID = try c.decodeIfPresent(String.self, forKey: .remoteID)
        uploadedAt = try c.decode(Date.self, forKey: .uploadedAt)
        webURL = try c.decodeIfPresent(String.self, forKey: .webURL)
        uploadId = try c.decodeIfPresent(Int.self, forKey: .uploadId)
    }
}

extension Array where Element == ServiceUploadRecord {
    /// Returns one record per service, preferring complete uploads over incomplete ones.
    func uniqueByService() -> [ServiceUploadRecord] {
        var best: [IntegrationServiceID: ServiceUploadRecord] = [:]
        for record in self {
            if let existing = best[record.service] {
                // Prefer the complete one
                if !existing.isComplete && record.isComplete {
                    best[record.service] = record
                }
            } else {
                best[record.service] = record
            }
        }
        return Array(best.values).sorted { $0.service.rawValue < $1.service.rawValue }
    }
}

// MARK: - Integration Settings

struct IntegrationSettings: Codable, Equatable {
    var services: [IntegrationServiceID: ServiceConfig]
    // Legacy — migrated to UserSettings.healthKitAutoUpload for watch sync
    var healthKitAutoUpload: Bool?

    struct ServiceConfig: Codable, Equatable {
        var isConnected: Bool
        var importRoutes: Bool
        var autoUpload: Bool

        static let disconnected = ServiceConfig(isConnected: false, importRoutes: false, autoUpload: false)
    }

    static let `default` = IntegrationSettings(
        services: [:]
    )

    func config(for service: IntegrationServiceID) -> ServiceConfig {
        services[service] ?? .disconnected
    }

    mutating func setConfig(_ config: ServiceConfig, for service: IntegrationServiceID) {
        services[service] = config
    }

    var connectedServices: [IntegrationServiceID] {
        IntegrationServiceID.oauthServices.filter { config(for: $0).isConnected }
    }

    var autoUploadDestinations: [IntegrationServiceID] {
        IntegrationServiceID.oauthServices.filter { config(for: $0).autoUpload }
    }

    var importRouteServices: [IntegrationServiceID] {
        IntegrationServiceID.oauthServices.filter { config(for: $0).isConnected && config(for: $0).importRoutes }
    }

    /// Count of auto-upload destinations (OAuth services only)
    var autoUploadCount: Int {
        autoUploadDestinations.count
    }
}

// MARK: - Service Route (API response model)

struct ServiceRoute: Identifiable {
    let id: String
    let name: String
    let distance: Double       // meters
    let elevationGain: Double  // meters
    let createdAt: Date
}
