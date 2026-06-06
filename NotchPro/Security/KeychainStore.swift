//
//  KeychainStore.swift
//  NotchPro
//

import Foundation
import LocalAuthentication
import Security

enum KeychainStore {
    private static let service = "com.ryana79.notchpro.credentials"

    static func save(_ value: String, account: String) throws {
        let data = Data(value.utf8)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]

        SecItemDelete(query as CFDictionary)

        var addQuery = query
        addQuery[kSecValueData as String] = data
        addQuery[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly

        let status = SecItemAdd(addQuery as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainError.saveFailed(status)
        }
    }

    static func load(account: String) -> String? {
        let context = LAContext()
        context.interactionNotAllowed = true

        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    static func delete(account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func deleteAll(accounts: [String]) {
        accounts.forEach { delete(account: $0) }
    }
}

enum KeychainError: LocalizedError {
    case saveFailed(OSStatus)

    var errorDescription: String? {
        switch self {
        case .saveFailed(let status):
            return "Could not save credentials securely (code \(status))."
        }
    }
}

enum BrokerCredentialKey {
    static let schwabAccessToken = "schwab.accessToken"
    static let schwabRefreshToken = "schwab.refreshToken"
    static let schwabTokenExpiry = "schwab.tokenExpiry"

    static let webullAccessToken = "webull.accessToken"
    static let webullTokenExpiry = "webull.tokenExpiry"
    static let webullAccountID = "webull.accountId"

    /// Per-user OAuth tokens only — app credentials live in BrokerCredentials.plist
    static let schwabUserTokens: [String] = [
        schwabAccessToken, schwabRefreshToken, schwabTokenExpiry,
    ]

    static let webullUserTokens: [String] = [
        webullAccessToken, webullTokenExpiry, webullAccountID,
    ]
}

enum IntegrationCredentialKey {
    static let groqAPIKey = "integrations.groqAPIKey"
}
