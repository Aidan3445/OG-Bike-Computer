//
//  OAuthManager.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import AuthenticationServices
import os
import Combine

private let logger = Logger(subsystem: "com.aidan3445.OG-Bike-Computer", category: "OAuth")

class OAuthManager: NSObject, ObservableObject {
    static let shared = OAuthManager()

    private var authSession: ASWebAuthenticationSession?
    private var presentationAnchor: ASPresentationAnchor?

    private override init() {
        super.init()
    }

    func setPresentationAnchor(_ anchor: ASPresentationAnchor) {
        self.presentationAnchor = anchor
    }

    // MARK: - Strava OAuth

    func authenticateStrava() async throws -> OAuthTokens {
        let clientID = StravaConfig.clientID
        let redirectURI = StravaConfig.redirectURI
        let scope = "activity:write,activity:read,read"

        let authURL = URL(string: "https://www.strava.com/oauth/mobile/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code&scope=\(scope)&approval_prompt=auto")!

        let callbackURL = try await startAuthSession(url: authURL, callbackScheme: StravaConfig.callbackScheme)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ServiceError.notAuthenticated
        }

        return try await exchangeStravaCode(code)
    }

    private func exchangeStravaCode(_ code: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.notAuthenticated
        }

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(tokenResponse.expires_at)),
            athleteID: "\(tokenResponse.athlete?.id ?? 0)"
        )
        KeychainHelper.saveTokens(tokens, for: .strava)
        return tokens
    }

    func refreshStravaToken() async throws -> OAuthTokens {
        guard let existing = KeychainHelper.loadTokens(for: .strava),
              let refreshToken = existing.refreshToken else {
            throw ServiceError.notAuthenticated
        }

        var request = URLRequest(url: URL(string: "https://www.strava.com/api/v3/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": StravaConfig.clientID,
            "client_secret": StravaConfig.clientSecret,
            "refresh_token": refreshToken,
            "grant_type": "refresh_token"
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.tokenExpired
        }

        let tokenResponse = try JSONDecoder().decode(StravaTokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: Date(timeIntervalSince1970: TimeInterval(tokenResponse.expires_at)),
            athleteID: existing.athleteID
        )
        KeychainHelper.saveTokens(tokens, for: .strava)
        return tokens
    }

    // MARK: - RWGPS OAuth

    func authenticateRWGPS() async throws -> OAuthTokens {
        let clientID = RWGPSConfig.clientID
        let redirectURI = RWGPSConfig.redirectURI

        let authURL = URL(string: "https://ridewithgps.com/oauth/authorize?client_id=\(clientID)&redirect_uri=\(redirectURI)&response_type=code")!

        let callbackURL = try await startAuthSession(url: authURL, callbackScheme: RWGPSConfig.callbackScheme)

        guard let components = URLComponents(url: callbackURL, resolvingAgainstBaseURL: false),
              let code = components.queryItems?.first(where: { $0.name == "code" })?.value else {
            throw ServiceError.notAuthenticated
        }

        return try await exchangeRWGPSCode(code)
    }

    private func exchangeRWGPSCode(_ code: String) async throws -> OAuthTokens {
        var request = URLRequest(url: URL(string: "https://ridewithgps.com/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = [
            "client_id": RWGPSConfig.clientID,
            "client_secret": RWGPSConfig.clientSecret,
            "code": code,
            "grant_type": "authorization_code",
            "redirect_uri": RWGPSConfig.redirectURI
        ]
        request.httpBody = try JSONEncoder().encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse, httpResponse.statusCode == 200 else {
            throw ServiceError.notAuthenticated
        }

        let tokenResponse = try JSONDecoder().decode(RWGPSTokenResponse.self, from: data)
        let tokens = OAuthTokens(
            accessToken: tokenResponse.access_token,
            refreshToken: tokenResponse.refresh_token,
            expiresAt: nil, // RWGPS tokens don't expire the same way
            athleteID: tokenResponse.user?.id.map { "\($0)" }
        )
        KeychainHelper.saveTokens(tokens, for: .rideWithGPS)
        return tokens
    }

    // MARK: - Shared Auth Session

    private func startAuthSession(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            DispatchQueue.main.async { [weak self] in
                let session = ASWebAuthenticationSession(
                    url: url,
                    callbackURLScheme: callbackScheme
                ) { callbackURL, error in
                    if let error {
                        continuation.resume(throwing: ServiceError.networkError(error))
                    } else if let callbackURL {
                        continuation.resume(returning: callbackURL)
                    } else {
                        continuation.resume(throwing: ServiceError.notAuthenticated)
                    }
                }
                session.presentationContextProvider = self
                session.prefersEphemeralWebBrowserSession = false
                self?.authSession = session
                session.start()
            }
        }
    }

    /// Get a valid access token for a service, refreshing if needed
    func validToken(for service: IntegrationServiceID) async throws -> String {
        guard let tokens = KeychainHelper.loadTokens(for: service) else {
            throw ServiceError.notAuthenticated
        }

        if tokens.isExpired {
            switch service {
            case .strava:
                let refreshed = try await refreshStravaToken()
                return refreshed.accessToken
            case .rideWithGPS:
                // RWGPS tokens don't expire in the same way
                return tokens.accessToken
            }
        }

        return tokens.accessToken
    }
}

// MARK: - ASWebAuthenticationPresentationContextProviding

extension OAuthManager: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        presentationAnchor ?? ASPresentationAnchor()
    }
}

// MARK: - Token Response Models

struct StravaTokenResponse: Codable {
    let access_token: String
    let refresh_token: String
    let expires_at: Int
    let athlete: StravaAthlete?
}

struct StravaAthlete: Codable {
    let id: Int
}

struct RWGPSTokenResponse: Codable {
    let access_token: String
    let refresh_token: String?
    let user: RWGPSUser?
}

struct RWGPSUser: Codable {
    let id: Int?
}
