//
//  SchwabAuthService.swift
//  NotchPro
//

import AppKit
import AuthenticationServices
import CryptoKit
import Foundation
import NotchProCore

@MainActor
final class SchwabAuthService: NSObject {
    static let shared = SchwabAuthService()

    static let redirectURI = "https://127.0.0.1:8765"
    static let customSchemeRedirectURI = "notchpro://oauth/schwab"

    private let baseURL = "https://api.schwabapi.com"
    private var pendingState: String?
    private var pendingVerifier: String?
    private var authSession: ASWebAuthenticationSession?

    private override init() {
        super.init()
    }

    func authorize() async throws -> String {
        let config = BrokerConfig.shared
        guard config.isSchwabConfigured else { throw BrokerageConnectionError.notConfigured(.schwab) }

        let state = UUID().uuidString
        let verifier = SchwabOAuthHelpers.generateCodeVerifier()
        let challenge = SchwabOAuthHelpers.codeChallenge(for: verifier)
        pendingState = state
        pendingVerifier = verifier

        var components = URLComponents(string: "\(baseURL)/v1/oauth/authorize")!
        components.queryItems = [
            URLQueryItem(name: "response_type", value: "code"),
            URLQueryItem(name: "client_id", value: config.schwabClientID),
            URLQueryItem(name: "redirect_uri", value: Self.redirectURI),
            URLQueryItem(name: "state", value: state),
            URLQueryItem(name: "code_challenge", value: challenge),
            URLQueryItem(name: "code_challenge_method", value: "S256"),
        ]

        guard let authURL = components.url else {
            throw BrokerageConnectionError.codeExchangeFailed
        }

        do {
            let callbackURL = try await startWebAuth(url: authURL, callbackScheme: "https")
            try validateCallback(callbackURL, expectedState: state)
            guard let code = SchwabOAuthHelpers.parseAuthorizationCode(from: callbackURL) else {
                throw BrokerageConnectionError.missingCode
            }
            return code
        } catch let error as BrokerageConnectionError {
            if case .loginCancelled = error { throw error }
            return try await fallbackLocalhostAuthorization(authURL: authURL, expectedState: state)
        } catch {
            return try await fallbackLocalhostAuthorization(authURL: authURL, expectedState: state)
        }
    }

    func exchangeCode(_ code: String) async throws -> BrokerTokenRecord {
        guard let verifier = pendingVerifier else {
            throw BrokerageConnectionError.codeExchangeFailed
        }

        let body: [String: String] = [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": Self.redirectURI,
            "code_verifier": verifier,
        ]

        let json = try await requestTokens(body: body)
        pendingVerifier = nil
        pendingState = nil
        return try Self.tokenRecord(from: json)
    }

    func refreshTokens(refreshToken: String) async throws -> BrokerTokenRecord {
        let json = try await requestTokens(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        return try Self.tokenRecord(from: json, existingRefresh: refreshToken)
    }

    func validAccessToken() async throws -> String {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        let record: BrokerTokenRecord
        do {
            record = try KeychainTokenStore.load(provider: .schwab)
        } catch KeychainTokenError.itemNotFound {
            throw BrokerageConnectionError.sessionExpired
        }

        if record.isAccessValid() {
            return record.accessToken
        }

        guard let refresh = record.refreshToken, record.isRefreshValid() else {
            throw BrokerageConnectionError.sessionExpired
        }

        let refreshed = try await refreshTokens(refreshToken: refresh)
        try KeychainTokenStore.save(refreshed, provider: .schwab)
        BrokerTokenCache.applySchwabRecord(refreshed)
        BrokerageDiagnostics.shared.updateTokenExpiries(schwab: refreshed, webull: try? KeychainTokenStore.load(provider: .webull))
        BrokerageDiagnostics.shared.recordKeychain("schwab_refresh_saved")
        return refreshed.accessToken
    }

    // MARK: - Private

    private func startWebAuth(url: URL, callbackScheme: String) async throws -> URL {
        try await withCheckedThrowingContinuation { continuation in
            let session = ASWebAuthenticationSession(
                url: url,
                callbackURLScheme: callbackScheme
            ) { callbackURL, error in
                if let error = error as? ASWebAuthenticationSessionError,
                   error.code == .canceledLogin {
                    continuation.resume(throwing: BrokerageConnectionError.loginCancelled)
                    return
                }
                if let error {
                    continuation.resume(throwing: error)
                    return
                }
                guard let callbackURL else {
                    continuation.resume(throwing: BrokerageConnectionError.missingCode)
                    return
                }
                continuation.resume(returning: callbackURL)
            }
            session.presentationContextProvider = self
            session.prefersEphemeralWebBrowserSession = false
            self.authSession = session
            if !session.start() {
                continuation.resume(throwing: BrokerageConnectionError.codeExchangeFailed)
            }
        }
    }

    private func fallbackLocalhostAuthorization(authURL: URL, expectedState: String) async throws -> String {
        let server = OAuthCallbackServer()
        try await server.prepare()
        NSWorkspace.shared.open(authURL)
        let code = try await server.waitForAuthorizationCode()
        server.stop()
        let callbackURL = URL(string: "\(Self.redirectURI)?code=\(code)&state=\(expectedState)")!
        try validateCallback(callbackURL, expectedState: expectedState)
        return code
    }

    private func validateCallback(_ url: URL, expectedState: String) throws {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else { return }
        if let returnedState = items.first(where: { $0.name == "state" })?.value,
           returnedState != expectedState {
            throw BrokerageConnectionError.stateMismatch
        }
        if items.contains(where: { $0.name == "error" }) {
            throw BrokerageConnectionError.authorizationExpired
        }
    }

    private func requestTokens(body: [String: String]) async throws -> [String: Any] {
        let config = BrokerConfig.shared
        guard let proxyURL = config.schwabTokenProxyURL else {
            throw BrokerageConnectionError.notConfigured(.schwab)
        }

        var payload = body
        if body["grant_type"] == "authorization_code", let verifier = pendingVerifier {
            payload["code_verifier"] = verifier
        }

        let response = try await BrokerHTTPClient.postJSON(
            url: proxyURL,
            body: payload,
            headers: config.brokerProxyAPIKey.isEmpty ? [:] : ["X-NotchPro-Key": config.brokerProxyAPIKey]
        )

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any] else {
            throw BrokerageConnectionError.codeExchangeFailed
        }
        return json
    }

    private static func tokenRecord(from json: [String: Any], existingRefresh: String? = nil) throws -> BrokerTokenRecord {
        guard let accessToken = json["access_token"] as? String else {
            throw BrokerageConnectionError.codeExchangeFailed
        }
        let refreshToken = (json["refresh_token"] as? String) ?? existingRefresh
        let expiresIn = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? 1800
        let refreshExpiresIn = (json["refresh_token_expires_in"] as? Double)
            ?? (json["refresh_token_expires_in"] as? Int).map(Double.init)

        return BrokerTokenRecord(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: Date().addingTimeInterval(expiresIn),
            refreshExpiresAt: refreshExpiresIn.map { Date().addingTimeInterval($0) },
            providerUserID: "default",
            scopes: json["scope"] as? String
        )
    }

    static func parseAuthorizationCode(from url: URL) -> String? {
        SchwabOAuthHelpers.parseAuthorizationCode(from: url)
    }

    static func codeChallenge(for verifier: String) -> String {
        SchwabOAuthHelpers.codeChallenge(for: verifier)
    }
}

extension SchwabAuthService: ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for session: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first { $0.isVisible } ?? NSWindow()
    }
}

extension BrokerTokenCache {
    static func applySchwabRecord(_ record: BrokerTokenRecord) {
        setSchwab(
            access: record.accessToken,
            refresh: record.refreshToken,
            expiry: String(record.expiresAt.timeIntervalSince1970)
        )
    }

    static func applyWebullRecord(_ record: BrokerTokenRecord, accountID: String?) {
        setWebull(
            access: record.accessToken,
            expiry: String(record.expiresAt.timeIntervalSince1970),
            accountID: accountID ?? record.providerUserID
        )
    }
}
