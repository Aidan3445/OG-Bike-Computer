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

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .rideWithGPS: return "Ride With GPS"
        case .strava: return "Strava"
        }
    }

    var iconAsset: String {
        switch self {
        case .rideWithGPS: return "RWGPSIcon"
        case .strava: return "StravaIcon"
        }
    }

    var brandColor: String {
        switch self {
        case .rideWithGPS: return "rwgpsOrange"
        case .strava: return "stravaOrange"
        }
    }
}

// MARK: - Route Source

struct RouteSource: Codable, Equatable {
    let service: IntegrationServiceID
    let remoteID: String
}

// MARK: - Upload Record

struct ServiceUploadRecord: Codable, Equatable, Identifiable {
    var id: String { "\(service.rawValue)-\(remoteID)" }
    let service: IntegrationServiceID
    let remoteID: String
    let uploadedAt: Date
    let webURL: String?
}

// MARK: - Integration Settings

struct IntegrationSettings: Codable, Equatable {
    var services: [IntegrationServiceID: ServiceConfig]
    var healthKitAutoUpload: Bool

    struct ServiceConfig: Codable, Equatable {
        var isConnected: Bool
        var importRoutes: Bool
        var autoUpload: Bool

        static let disconnected = ServiceConfig(isConnected: false, importRoutes: false, autoUpload: false)
    }

    static let `default` = IntegrationSettings(
        services: [:],
        healthKitAutoUpload: true
    )

    func config(for service: IntegrationServiceID) -> ServiceConfig {
        services[service] ?? .disconnected
    }

    mutating func setConfig(_ config: ServiceConfig, for service: IntegrationServiceID) {
        services[service] = config
    }

    var connectedServices: [IntegrationServiceID] {
        IntegrationServiceID.allCases.filter { config(for: $0).isConnected }
    }

    var autoUploadDestinations: [IntegrationServiceID] {
        IntegrationServiceID.allCases.filter { config(for: $0).autoUpload }
    }

    var importRouteServices: [IntegrationServiceID] {
        IntegrationServiceID.allCases.filter { config(for: $0).isConnected && config(for: $0).importRoutes }
    }

    /// Count of auto-upload destinations including HealthKit
    var totalAutoUploadCount: Int {
        autoUploadDestinations.count + (healthKitAutoUpload ? 1 : 0)
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
