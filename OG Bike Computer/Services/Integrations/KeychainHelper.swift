//
//  KeychainHelper.swift
//  OG Bike Computer
//
//  Created by Aidan Weinberg on 3/31/26.
//

import Foundation
import Security

struct OAuthTokens: Codable {
    let accessToken: String
    let refreshToken: String?
    let expiresAt: Date?
    let athleteID: String?

    var isExpired: Bool {
        guard let expiresAt else { return false }
        return Date() >= expiresAt
    }
}

enum KeychainHelper {
    private static func serviceKey(for service: IntegrationServiceID) -> String {
        "com.ogbikecomputer.oauth.\(service.rawValue)"
    }

    static func saveTokens(_ tokens: OAuthTokens, for service: IntegrationServiceID) {
        guard let data = try? JSONEncoder().encode(tokens) else { return }
        let key = serviceKey(for: service)

        // Delete existing first
        let deleteQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key
        ]
        SecItemDelete(deleteQuery as CFDictionary)

        let addQuery: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock
        ]
        SecItemAdd(addQuery as CFDictionary, nil)
    }

    static func loadTokens(for service: IntegrationServiceID) -> OAuthTokens? {
        let key = serviceKey(for: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(OAuthTokens.self, from: data)
    }

    static func deleteTokens(for service: IntegrationServiceID) {
        let key = serviceKey(for: service)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: key
        ]
        SecItemDelete(query as CFDictionary)
    }
}
