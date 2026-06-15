//
//  KeychainTokenStore.swift
//  NotchProCore
//

import Foundation
import LocalAuthentication
import Security

public struct BrokerTokenRecord: Codable, Equatable, Sendable {
    public var accessToken: String
    public var refreshToken: String?
    public var expiresAt: Date
    public var refreshExpiresAt: Date?
    public var providerUserID: String
    public var scopes: String?

    public init(
        accessToken: String,
        refreshToken: String?,
        expiresAt: Date,
        refreshExpiresAt: Date?,
        providerUserID: String,
        scopes: String?
    ) {
        self.accessToken = accessToken
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.refreshExpiresAt = refreshExpiresAt
        self.providerUserID = providerUserID
        self.scopes = scopes
    }

    public func isAccessValid(buffer: TimeInterval = 180) -> Bool {
        Date().addingTimeInterval(buffer) < expiresAt
    }

    public func isRefreshValid(buffer: TimeInterval = 300) -> Bool {
        guard let refreshExpiresAt else { return refreshToken != nil }
        return Date().addingTimeInterval(buffer) < refreshExpiresAt
    }
}

public enum KeychainTokenError: LocalizedError, Equatable, Sendable {
    case itemNotFound
    case duplicateItem
    case interactionNotAllowed
    case missingEntitlement
    case authFailed
    case saveFailed(OSStatus)
    case decodeFailed

    public var debugCode: String {
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

    public var errorDescription: String? {
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

public enum KeychainTokenStore {
    public static let service = "com.ryana79.notchpro.brokerage.tokens"

    public static func accountKey(provider: BrokerageProvider, userID: String = "default") -> String {
        "\(provider.rawValue).\(userID)"
    }

    public static func save(_ record: BrokerTokenRecord, provider: BrokerageProvider) throws {
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

    public static func load(provider: BrokerageProvider, userID: String = "default") throws -> BrokerTokenRecord {
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

    public static func delete(provider: BrokerageProvider, userID: String = "default") {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: accountKey(provider: provider, userID: userID),
        ]
        SecItemDelete(query as CFDictionary)
    }
}
