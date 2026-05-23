//
//  ConnectivityError.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 2/28/26.
//

import Foundation

enum ConnectivityError: LocalizedError {
    case notSupported
    case notPaired
    case watchAppNotInstalled
    case companionAppNotInstalled
    case notReachable
    case notActivated
    case encodingFailed
    case watchOperationFailed(String)

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Apple Watch is not supported on this device."
        case .notPaired:
            return "No Apple Watch is paired with this iPhone."
        case .watchAppNotInstalled:
            return "The OG Bike Computer app is not installed on your Apple Watch."
        case .companionAppNotInstalled:
            return "The companion iPhone app is not installed."
        case .notReachable:
            return "Companion device is not reachable right now."
        case .notActivated:
            return "WCSession has not been activated yet."
        case .encodingFailed:
            return "Failed to encode route data for transmission."
        case .watchOperationFailed(let reason):
            return reason
        }
    }
}
