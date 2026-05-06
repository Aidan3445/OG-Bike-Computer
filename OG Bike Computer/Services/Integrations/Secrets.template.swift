//
//  Secrets.swift
//  OG Bike Computer
//
//  This file contains API credentials for third-party integrations.
//  Copy this file to Secrets.swift and fill in your actual credentials.
//  Secrets.swift is gitignored and should never be committed to version control.
//

import Foundation

// MARK: - Strava Configuration

struct TEMPLATEStravaConfig {
    /// OAuth Client ID from https://www.strava.com/settings/api
    static let clientID = "YOUR_STRAVA_CLIENT_ID"

    /// OAuth Client Secret from https://www.strava.com/settings/api
    static let clientSecret = "YOUR_STRAVA_CLIENT_SECRET"

    /// Redirect URI configured in Strava OAuth settings
    static let redirectURI = "ogbikecomputer://aidan3445.github.io"

    /// URL scheme for handling OAuth callbacks
    static let callbackScheme = "ogbikecomputer"
}

// MARK: - Ride With GPS Configuration

struct TEMPLATERWGPSConfig {
    /// OAuth Client ID from https://ridewithgps.com/oauth/applications
    static let clientID = "YOUR_RWGPS_CLIENT_ID"

    /// OAuth Client Secret from https://ridewithgps.com/oauth/applications
    static let clientSecret = "YOUR_RWGPS_CLIENT_SECRET"

    /// API Key from https://ridewithgps.com/api
    static let apiKey = "YOUR_RWGPS_API_KEY"

    /// API Secret from https://ridewithgps.com/api
    static let apiSecret = "YOUR_RWGPS_API_SECRET"

    /// Redirect URI configured in RWGPS OAuth settings
    static let redirectURI = "ogbikecomputer://aidan3445.github.io"

    /// URL scheme for handling OAuth callbacks
    static let callbackScheme = "ogbikecomputer"
}
