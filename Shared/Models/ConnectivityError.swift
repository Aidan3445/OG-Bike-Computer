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
    case notReachable
    case encodingFailed

    var errorDescription: String? {
        switch self {
        case .notSupported:
            return "Apple Watch is not supported on this device."
        case .notPaired:
            return "No Apple Watch is paired with this iPhone."
        case .watchAppNotInstalled:
            return "The OG Bike Computer app is not installed on your Apple Watch."
        case .notReachable:
            return "Apple Watch is not reachable right now."
        case .encodingFailed:
            return "Failed to encode route data for transmission."
        }
    }
}
