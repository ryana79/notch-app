//
//  KeychainTokenStore+Migration.swift
//  NotchPro
//

import Foundation
import NotchProCore

extension KeychainTokenStore {
    private static let migrationKey = "brokerage.tokens.migrated.v1"

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
