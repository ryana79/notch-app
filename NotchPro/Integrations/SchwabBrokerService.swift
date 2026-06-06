//
//  SchwabBrokerService.swift
//  NotchPro
//

import AppKit
import Defaults
import Foundation

struct PortfolioHolding: Identifiable, Equatable {
    let id: String
    let broker: BrokerKind
    let symbol: String
    let quantity: Double
    let marketValue: Double
    let dayChange: Double?
    let dayChangePercent: Double?
}

struct PortfolioSnapshot: Equatable {
    let totalMarketValue: Double
    let totalDayChange: Double
    let holdings: [PortfolioHolding]
    let lastUpdated: Date
    let brokersConnected: [BrokerKind]
}

enum BrokerKind: String, CaseIterable, Codable, Defaults.Serializable {
    case schwab
    case webull

    var displayName: String {
        switch self {
        case .schwab: return "Schwab"
        case .webull: return "Webull"
        }
    }
}

enum BrokerConnectionState: Equatable {
    case disconnected
    case connecting
    case awaitingVerification(String)
    case connected
    case error(String)
}

enum SchwabBrokerError: LocalizedError {
    case notConfigured
    case missingTokens
    case invalidResponse
    case apiError(String)
    case authRequired

    var errorDescription: String? {
        switch self {
        case .notConfigured: return "Schwab isn’t set up in this build of NotchPro yet."
        case .missingTokens: return "Tap Connect Schwab to link your account."
        case .invalidResponse: return "Unexpected response from Schwab."
        case .apiError(let message): return message
        case .authRequired: return "Schwab session expired — tap Connect Schwab again."
        }
    }
}

@MainActor
final class SchwabBrokerService {
    static let shared = SchwabBrokerService()

    private let baseURL = "https://api.schwabapi.com"
    private let session: URLSession
    private var callbackServer: OAuthCallbackServer?

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        BrokerConnectionCache.schwabConnected
    }

    func disconnect() {
        callbackServer?.stop()
        callbackServer = nil
        KeychainStore.deleteAll(accounts: BrokerCredentialKey.schwabUserTokens)
        BrokerTokenCache.clearSchwab()
        BrokerConnectionCache.setSchwabConnected(false)
    }

    func connect() async throws {
        let config = BrokerConfig.shared
        guard config.isSchwabConfigured else { throw SchwabBrokerError.notConfigured }

        let server = OAuthCallbackServer()
        callbackServer = server

        let clientID = config.schwabClientID
        let authURL = URL(string: """
        \(baseURL)/v1/oauth/authorize?response_type=code&client_id=\(clientID.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? clientID)&redirect_uri=\(OAuthCallbackServer.redirectURI.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? OAuthCallbackServer.redirectURI)
        """)!

        NSWorkspace.shared.open(authURL)

        let code = try await server.waitForAuthorizationCode()
        callbackServer = nil

        try await exchangeCode(code)
    }

    func connect(manualRedirectURL: String) async throws {
        guard BrokerConfig.shared.isSchwabConfigured else { throw SchwabBrokerError.notConfigured }

        guard let code = Self.parseCode(from: manualRedirectURL) else {
            throw SchwabBrokerError.apiError("Could not find authorization code in that URL.")
        }

        try await exchangeCode(code)
    }

    func fetchHoldings() async throws -> [PortfolioHolding] {
        let token = try await validAccessToken()
        let accountHashes = try await fetchAccountHashes(accessToken: token)
        var holdings: [PortfolioHolding] = []

        for hash in accountHashes {
            let accountHoldings = try await fetchPositions(accountHash: hash, accessToken: token)
            holdings.append(contentsOf: accountHoldings)
        }

        return holdings
    }

    private func exchangeCode(_ code: String) async throws {
        let json = try await requestTokens(body: [
            "grant_type": "authorization_code",
            "code": code,
            "redirect_uri": OAuthCallbackServer.redirectURI,
        ])
        try persistTokenResponse(json)
    }

    private func validAccessToken() async throws -> String {
        if let expiryString = BrokerTokenCache.schwabExpiry(),
           let expiryInterval = TimeInterval(expiryString),
           Date().timeIntervalSince1970 < expiryInterval - 60,
           let token = BrokerTokenCache.schwabAccess() {
            return token
        }
        return try await refreshAccessToken()
    }

    private func refreshAccessToken() async throws -> String {
        guard let refreshToken = BrokerTokenCache.schwabRefresh() else {
            throw SchwabBrokerError.authRequired
        }

        let json = try await requestTokens(body: [
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        try persistTokenResponse(json)
        guard let access = json["access_token"] as? String else {
            throw SchwabBrokerError.invalidResponse
        }
        return access
    }

    private func requestTokens(body: [String: String]) async throws -> [String: Any] {
        let config = BrokerConfig.shared

        if let proxyURL = config.schwabTokenProxyURL {
            do {
                return try await requestTokensViaProxy(proxyURL: proxyURL, body: body, apiKey: config.brokerProxyAPIKey)
            } catch {
                if !config.schwabClientSecret.isEmpty {
                    return try await requestTokensDirect(body: body, config: config)
                }
                throw error
            }
        }

        guard !config.schwabClientSecret.isEmpty else {
            throw SchwabBrokerError.notConfigured
        }

        return try await requestTokensDirect(body: body, config: config)
    }

    private func requestTokensViaProxy(proxyURL: URL, body: [String: String], apiKey: String) async throws -> [String: Any] {
        var request = URLRequest(url: proxyURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if !apiKey.isEmpty {
            request.setValue(apiKey, forHTTPHeaderField: "X-NotchPro-Key")
        }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw SchwabBrokerError.invalidResponse }

        if http.statusCode == 401, String(data: data, encoding: .utf8)?.contains("<!doctype html>") == true {
            throw SchwabBrokerError.apiError(
                "Schwab token proxy is unreachable. Use https://broker-proxy.vercel.app/api/schwab/token"
            )
        }

        if http.statusCode == 401 {
            throw SchwabBrokerError.authRequired
        }

        try validateHTTP(response: response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchwabBrokerError.invalidResponse
        }
        return json
    }

    private func requestTokensDirect(body: [String: String], config: BrokerConfig) async throws -> [String: Any] {
        var request = URLRequest(url: URL(string: "\(baseURL)/v1/oauth/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let credentials = Data("\(config.schwabClientID):\(config.schwabClientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(credentials)", forHTTPHeaderField: "Authorization")
        request.httpBody = body
            .map { "\($0.key)=\($0.value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? $0.value)" }
            .joined(separator: "&")
            .data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 {
            throw SchwabBrokerError.authRequired
        }
        try validateHTTP(response: response, data: data)
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw SchwabBrokerError.invalidResponse
        }
        return json
    }

    private func persistTokenResponse(_ json: [String: Any]) throws {
        guard let accessToken = json["access_token"] as? String else {
            throw SchwabBrokerError.invalidResponse
        }

        try KeychainStore.save(accessToken, account: BrokerCredentialKey.schwabAccessToken)

        var refreshToken: String? = json["refresh_token"] as? String
        if let newRefresh = refreshToken {
            try KeychainStore.save(newRefresh, account: BrokerCredentialKey.schwabRefreshToken)
        } else {
            refreshToken = BrokerTokenCache.schwabRefresh()
        }

        let expiresIn = (json["expires_in"] as? Double) ?? (json["expires_in"] as? Int).map(Double.init) ?? 1800
        let expiry = Date().addingTimeInterval(expiresIn)
        let expiryString = String(expiry.timeIntervalSince1970)
        try KeychainStore.save(expiryString, account: BrokerCredentialKey.schwabTokenExpiry)
        BrokerTokenCache.setSchwab(access: accessToken, refresh: refreshToken, expiry: expiryString)
        BrokerConnectionCache.setSchwabConnected(true)
    }

    private func fetchAccountHashes(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(baseURL)/trader/v1/accounts/accountNumbers")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw SchwabBrokerError.authRequired }
        try validateHTTP(response: response, data: data)

        guard let accounts = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw SchwabBrokerError.invalidResponse
        }

        return accounts.compactMap { $0["hashValue"] as? String }
    }

    private func fetchPositions(accountHash: String, accessToken: String) async throws -> [PortfolioHolding] {
        var components = URLComponents(string: "\(baseURL)/trader/v1/accounts/\(accountHash)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "positions")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 401 { throw SchwabBrokerError.authRequired }
        try validateHTTP(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let securitiesAccount = json["securitiesAccount"] as? [String: Any],
              let positions = securitiesAccount["positions"] as? [[String: Any]] else {
            return []
        }

        return positions.compactMap { position in
            guard let instrument = position["instrument"] as? [String: Any],
                  let symbol = instrument["symbol"] as? String else { return nil }

            let quantity = (position["longQuantity"] as? Double) ?? 0
            let marketValue = (position["marketValue"] as? Double) ?? 0
            let dayPL = position["currentDayProfitLoss"] as? Double
            let dayPLPercent = position["currentDayProfitLossPercentage"] as? Double

            return PortfolioHolding(
                id: "schwab-\(symbol)",
                broker: .schwab,
                symbol: symbol,
                quantity: quantity,
                marketValue: marketValue,
                dayChange: dayPL,
                dayChangePercent: dayPLPercent
            )
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw SchwabBrokerError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw SchwabBrokerError.apiError(message)
        }
    }

    private static func parseCode(from input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("code="), let url = URL(string: trimmed) {
            return URLComponents(url: url, resolvingAgainstBaseURL: false)?
                .queryItems?
                .first(where: { $0.name == "code" })?
                .value
        }
        if !trimmed.contains("/"), !trimmed.contains("=") { return trimmed }
        return nil
    }
}
