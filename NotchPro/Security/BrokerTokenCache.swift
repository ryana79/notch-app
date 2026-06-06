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
        schwabAccessToken = KeychainStore.load(account: BrokerCredentialKey.schwabAccessToken)
        return schwabAccessToken
    }

    static func schwabRefresh() -> String? {
        if let cached = schwabRefreshToken { return cached }
        schwabRefreshToken = KeychainStore.load(account: BrokerCredentialKey.schwabRefreshToken)
        return schwabRefreshToken
    }

    static func schwabExpiry() -> String? {
        if let cached = schwabTokenExpiry { return cached }
        schwabTokenExpiry = KeychainStore.load(account: BrokerCredentialKey.schwabTokenExpiry)
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
        webullAccessToken = KeychainStore.load(account: BrokerCredentialKey.webullAccessToken)
        return webullAccessToken
    }

    static func webullExpiry() -> String? {
        if let cached = webullTokenExpiry { return cached }
        webullTokenExpiry = KeychainStore.load(account: BrokerCredentialKey.webullTokenExpiry)
        return webullTokenExpiry
    }

    static func webullAccountID() -> String? {
        if let cached = cachedWebullAccountID { return cached }
        cachedWebullAccountID = KeychainStore.load(account: BrokerCredentialKey.webullAccountID)
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
        _ = schwabRefresh()
        _ = schwabAccess()
        _ = schwabExpiry()
    }

    static func warmWebullFromKeychain() {
        _ = webullAccess()
        _ = webullExpiry()
        _ = webullAccountID()
    }
}
