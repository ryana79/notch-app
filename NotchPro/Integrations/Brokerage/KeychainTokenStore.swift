//
//  KeychainTokenStore.swift
//  NotchPro
//

import Foundation
import LocalAuthentication
import Security

struct BrokerTokenRecord: Codable, Equatable {
    var accessToken: String
    var refreshToken: String?
    var expiresAt: Date
    var refreshExpiresAt: Date?
    var providerUserID: String
    var scopes: String?

    func isAccessValid(buffer: TimeInterval = 180) -> Bool {
        Date().addingTimeInterval(buffer) < expiresAt
    }

    func isRefreshValid(buffer: TimeInterval = 300) -> Bool {
        guard let refreshExpiresAt else { return refreshToken != nil }
        return Date().addingTimeInterval(buffer) < refreshExpiresAt
    }
}

enum KeychainTokenError: LocalizedError, Equatable {
    case itemNotFound
    case duplicateItem
    case interactionNotAllowed
    case missingEntitlement
    case authFailed
    case saveFailed(OSStatus)
    case decodeFailed

    var debugCode: String {
        switch self {
        case .itemNotFound: return "item_not_found"
        case .duplicateItem: return "duplicate_item"
        case .interactionNotAllowed: return "interaction_not_allowed"
        case .missingEntitlement: return "missing_entitlement"
        case .authFailed: return "auth_failed"
        case .saveFailed: return "save_failed"
        case .decodeFailed: return "decode_failed"
        }
    }

    var errorDescription: String? {
        switch self {
        case .itemNotFound:
            return "No saved brokerage session was found."
        case .duplicateItem:
            return "Could not update saved credentials securely."
        case .interactionNotAllowed, .authFailed, .missingEntitlement:
            return "Could not access saved credentials securely."
        case .saveFailed(let status):
            return "Could not save credentials securely (code \(status))."
        case .decodeFailed:
            return "Saved credentials were unreadable."
        }
    }
}

enum KeychainTokenStore {
    static let service = "com.ryana79.notchpro.brokerage.tokens"
    private static let migrationKey = "brokerage.tokens.migrated.v1"

    static func accountKey(provider: BrokerageProvider, userID: String = "default") -> String {
        "\(provider.rawValue).\(userID)"
    }

    static func save(_ record: BrokerTokenRecord, provider: BrokerageProvider) throws {
        let data = try JSONEncoder().encode(record)
        let account = accountKey(provider: provider, userID: record.providerUserID)

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
            throw KeychainTokenError.saveFailed(status)
        }
    }

    static func load(provider: BrokerageProvider, userID: String = "default") throws -> BrokerTokenRecord {
        let context = LAContext()
        context.interactionNotAllowed = true

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(provider: provider, userID: userID),
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationUI as String: kSecUseAuthenticationUIFail,
            kSecUseAuthenticationContext as String: context,
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            break
        case errSecItemNotFound:
            throw KeychainTokenError.itemNotFound
        case errSecInteractionNotAllowed:
            throw KeychainTokenError.interactionNotAllowed
        case errSecAuthFailed:
            throw KeychainTokenError.authFailed
        default:
            if status == errSecMissingEntitlement {
                throw KeychainTokenError.missingEntitlement
            }
            throw KeychainTokenError.saveFailed(status)
        }

        guard let data = item as? Data,
              let record = try? JSONDecoder().decode(BrokerTokenRecord.self, from: data) else {
            throw KeychainTokenError.decodeFailed
        }
        return record
    }

    static func delete(provider: BrokerageProvider, userID: String = "default") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(provider: provider, userID: userID),
        ]
        SecItemDelete(query as CFDictionary)
    }

    static func migrateFromLegacyIfNeeded() {
        guard !UserDefaults.standard.bool(forKey: migrationKey) else { return }

        if let access = KeychainStore.load(account: BrokerCredentialKey.schwabAccessToken) {
            let refresh = KeychainStore.load(account: BrokerCredentialKey.schwabRefreshToken)
            let expiryString = KeychainStore.load(account: BrokerCredentialKey.schwabTokenExpiry)
            let expiry = expiryString.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
                ?? Date().addingTimeInterval(1800)
            let record = BrokerTokenRecord(
                accessToken: access,
                refreshToken: refresh,
                expiresAt: expiry,
                refreshExpiresAt: nil,
                providerUserID: "default",
                scopes: nil
            )
            try? save(record, provider: .schwab)
        }

        if let access = KeychainStore.load(account: BrokerCredentialKey.webullAccessToken) {
            let expiryString = KeychainStore.load(account: BrokerCredentialKey.webullTokenExpiry)
            let expiry = expiryString.flatMap { TimeInterval($0) }.map { Date(timeIntervalSince1970: $0) }
                ?? Date().addingTimeInterval(30 * 60)
            let accountID = KeychainStore.load(account: BrokerCredentialKey.webullAccountID) ?? "default"
            let record = BrokerTokenRecord(
                accessToken: access,
                refreshToken: nil,
                expiresAt: expiry,
                refreshExpiresAt: Date().addingTimeInterval(15 * 24 * 3600),
                providerUserID: accountID,
                scopes: nil
            )
            try? save(record, provider: .webull)
        }

        UserDefaults.standard.set(true, forKey: migrationKey)
    }
}
