//
//  BrokerTokenCache.swift
//  NotchPro
//

import Foundation

/// In-memory broker token cache — one keychain read per session, not per API call.
@MainActor
enum BrokerTokenCache {
    private static var schwabAccessToken: String?
    private static var schwabRefreshToken: String?
    private static var schwabTokenExpiry: String?
    private static var webullAccessToken: String?
    private static var webullTokenExpiry: String?
    private static var cachedWebullAccountID: String?

    static func schwabAccess() -> String? {
        if let cached = schwabAccessToken { return cached }
        warmSchwabFromKeychain()
        return schwabAccessToken
    }

    static func schwabRefresh() -> String? {
        if let cached = schwabRefreshToken { return cached }
        warmSchwabFromKeychain()
        return schwabRefreshToken
    }

    static func schwabExpiry() -> String? {
        if let cached = schwabTokenExpiry { return cached }
        warmSchwabFromKeychain()
        return schwabTokenExpiry
    }

    static func setSchwab(access: String?, refresh: String?, expiry: String?) {
        schwabAccessToken = access
        schwabRefreshToken = refresh
        schwabTokenExpiry = expiry
    }

    static func clearSchwab() {
        schwabAccessToken = nil
        schwabRefreshToken = nil
        schwabTokenExpiry = nil
    }

    static func webullAccess() -> String? {
        if let cached = webullAccessToken { return cached }
        warmWebullFromKeychain()
        return webullAccessToken
    }

    static func webullExpiry() -> String? {
        if let cached = webullTokenExpiry { return cached }
        warmWebullFromKeychain()
        return webullTokenExpiry
    }

    static func webullAccountID() -> String? {
        if let cached = cachedWebullAccountID { return cached }
        warmWebullFromKeychain()
        return cachedWebullAccountID
    }

    static func setWebull(access: String?, expiry: String?, accountID: String?) {
        webullAccessToken = access
        webullTokenExpiry = expiry
        cachedWebullAccountID = accountID
    }

    static func clearWebull() {
        webullAccessToken = nil
        webullTokenExpiry = nil
        cachedWebullAccountID = nil
    }

    static func warmSchwabFromKeychain() {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        if let record = try? KeychainTokenStore.load(provider: .schwab) {
            applySchwabRecord(record)
        }
    }

    static func warmWebullFromKeychain() {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        if let record = try? KeychainTokenStore.load(provider: .webull) {
            applyWebullRecord(record, accountID: record.providerUserID)
        }
    }
}
