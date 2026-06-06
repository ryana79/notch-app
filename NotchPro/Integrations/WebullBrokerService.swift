//
//  WebullBrokerService.swift
//  NotchPro
//

import CryptoKit
import Foundation

enum WebullBrokerError: LocalizedError {
    case notConfigured
    case missingToken
    case awaitingVerification
    case smsExpired
    case sessionExpired
    case invalidResponse
    case apiError(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Webull isn’t set up in this build of NotchPro yet."
        case .missingToken:
            return "Tap Connect Webull to link your account."
        case .awaitingVerification:
            return "Check the Webull app and enter the SMS code to finish connecting."
        case .smsExpired:
            return "SMS code expired. Tap Connect Webull again for a new code."
        case .sessionExpired:
            return "Webull session expired. Tap Connect Webull to sign in again."
        case .invalidResponse:
            return "Unexpected response from Webull."
        case .apiError(let message):
            if message.lowercased().contains("unauthorized") {
                return "Webull session expired. Tap Connect Webull to sign in again."
            }
            return message
        }
    }
}

@MainActor
final class WebullBrokerService {
    static let shared = WebullBrokerService()

    private let host = "api.webull.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        BrokerConnectionCache.webullConnected
    }

    private var appKey: String { BrokerConfig.shared.webullAppKey }
    private var appSecret: String { BrokerConfig.shared.webullAppSecret }

    func disconnect() {
        KeychainStore.deleteAll(accounts: BrokerCredentialKey.webullUserTokens)
        BrokerTokenCache.clearWebull()
        BrokerConnectionCache.setWebullConnected(false)
    }

    func connect(onPendingVerification: (() -> Void)? = nil) async throws {
        guard BrokerConfig.shared.isWebullConfigured else { throw WebullBrokerError.notConfigured }

        disconnect()

        let tokenResponse = try await createToken(appKey: appKey, appSecret: appSecret)
        let status = (tokenResponse["status"] as? String) ?? ""

        if status.uppercased() == "NORMAL", let token = tokenResponse["token"] as? String {
            try persistToken(token, tokenResponse: tokenResponse)
            return
        }

        if status.uppercased() == "PENDING", let pendingToken = tokenResponse["token"] as? String {
            onPendingVerification?()
            try await pollUntilVerified(appKey: appKey, appSecret: appSecret, pendingToken: pendingToken)
            return
        }

        throw WebullBrokerError.apiError("Token status: \(status)")
    }

    func fetchHoldings() async throws -> [PortfolioHolding] {
        guard BrokerConfig.shared.isWebullConfigured else { throw WebullBrokerError.notConfigured }
        guard let accessToken = BrokerTokenCache.webullAccess() else {
            throw WebullBrokerError.missingToken
        }

        let accountID: String
        if let saved = BrokerTokenCache.webullAccountID() {
            accountID = saved
        } else {
            accountID = try await fetchPrimaryAccountID(appKey: appKey, appSecret: appSecret, accessToken: accessToken)
            try KeychainStore.save(accountID, account: BrokerCredentialKey.webullAccountID)
            BrokerTokenCache.setWebull(
                access: accessToken,
                expiry: BrokerTokenCache.webullExpiry(),
                accountID: accountID
            )
        }

        let path = "/openapi/account/positions"
        let query = ["account_id": accountID]
        let (data, response) = try await signedRequest(
            method: "GET",
            path: path,
            query: query,
            body: nil,
            appKey: appKey,
            appSecret: appSecret,
            accessToken: accessToken
        )
        try validateHTTP(response: response, data: data)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let holdings = json["holdings"] as? [[String: Any]] ?? json["positions"] as? [[String: Any]] else {
            if let array = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
                return parseHoldings(array)
            }
            return []
        }

        return parseHoldings(holdings)
    }

    private func parseHoldings(_ items: [[String: Any]]) -> [PortfolioHolding] {
        items.compactMap { item in
            let symbol = (item["symbol"] as? String)
                ?? (item["ticker"] as? String)
                ?? (item["ticker_id"] as? String)
            guard let symbol else { return nil }

            let quantity = doubleValue(item["quantity"] ?? item["qty"] ?? item["position_qty"])
            let marketValue = doubleValue(item["market_value"] ?? item["marketValue"] ?? item["position_value"])
            let dayChange = doubleValue(item["unrealized_day_profit_loss"] ?? item["day_profit_loss"])
            let dayChangePercent = doubleValue(item["unrealized_day_profit_loss_rate"] ?? item["day_profit_loss_ratio"])

            return PortfolioHolding(
                id: "webull-\(symbol)",
                broker: .webull,
                symbol: symbol,
                quantity: quantity,
                marketValue: marketValue,
                dayChange: dayChange == 0 ? nil : dayChange,
                dayChangePercent: dayChangePercent == 0 ? nil : dayChangePercent
            )
        }
    }

    private func doubleValue(_ value: Any?) -> Double {
        if let d = value as? Double { return d }
        if let i = value as? Int { return Double(i) }
        if let s = value as? String { return Double(s) ?? 0 }
        return 0
    }

    private func createToken(appKey: String, appSecret: String) async throws -> [String: Any] {
        let path = "/openapi/auth/token/create"
        let body = "{}".data(using: .utf8)!
        let (data, response) = try await signedTokenRequest(
            method: "POST",
            path: path,
            body: body,
            appKey: appKey,
            appSecret: appSecret
        )
        try validateTokenHTTP(response: response, data: data)
        return try parseJSONObject(data)
    }

    private func pollUntilVerified(appKey: String, appSecret: String, pendingToken: String) async throws {
        var activePendingToken = pendingToken
        var smsRetries = 0

        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(5))
            let statusResponse = try await checkToken(
                appKey: appKey,
                appSecret: appSecret,
                token: activePendingToken
            )
            let status = (statusResponse["status"] as? String) ?? ""
            if status.uppercased() == "NORMAL", let token = statusResponse["token"] as? String {
                try persistToken(token, tokenResponse: statusResponse)
                return
            }
            if status.uppercased() == "EXPIRED" || status.uppercased() == "INVALID" {
                guard smsRetries < 2 else { throw WebullBrokerError.smsExpired }
                smsRetries += 1
                let fresh = try await createToken(appKey: appKey, appSecret: appSecret)
                let freshStatus = (fresh["status"] as? String) ?? ""
                if freshStatus.uppercased() == "NORMAL", let token = fresh["token"] as? String {
                    try persistToken(token, tokenResponse: fresh)
                    return
                }
                if freshStatus.uppercased() == "PENDING", let newPending = fresh["token"] as? String {
                    activePendingToken = newPending
                    continue
                }
                throw WebullBrokerError.smsExpired
            }
        }
        throw WebullBrokerError.awaitingVerification
    }

    private func checkToken(appKey: String, appSecret: String, token: String) async throws -> [String: Any] {
        let path = "/openapi/auth/token/check"
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let (data, response) = try await signedTokenRequest(
            method: "POST",
            path: path,
            body: body,
            appKey: appKey,
            appSecret: appSecret
        )
        try validateTokenHTTP(response: response, data: data)
        return try parseJSONObject(data)
    }

    private func signedTokenRequest(
        method: String,
        path: String,
        body: Data?,
        appKey: String,
        appSecret: String
    ) async throws -> (Data, URLResponse) {
        let timestamp = Self.utcTimestamp()
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        let signature = Self.generateSignature(
            path: path,
            query: [:],
            bodyString: bodyString,
            appKey: appKey,
            appSecret: appSecret,
            host: host,
            timestamp: timestamp,
            nonce: nonce
        )

        var request = URLRequest(url: URL(string: "https://\(host)\(path)")!)
        request.httpMethod = method
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.setValue(signature, forHTTPHeaderField: "x-signature")
        request.setValue("HMAC-SHA1", forHTTPHeaderField: "x-signature-algorithm")
        request.setValue("1.0", forHTTPHeaderField: "x-signature-version")
        request.setValue(nonce, forHTTPHeaderField: "x-signature-nonce")
        request.setValue("v2", forHTTPHeaderField: "x-version")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return try await session.data(for: request)
    }

    private func persistToken(_ token: String, tokenResponse: [String: Any]) throws {
        try KeychainStore.save(token, account: BrokerCredentialKey.webullAccessToken)
        BrokerConnectionCache.setWebullConnected(true)
        var expiryString: String?
        if let expiresMs = tokenResponse["expires"] as? Int {
            let expiry = Date(timeIntervalSince1970: Double(expiresMs) / 1000)
            expiryString = String(expiry.timeIntervalSince1970)
            try KeychainStore.save(expiryString!, account: BrokerCredentialKey.webullTokenExpiry)
        } else if let expiresMs = tokenResponse["expires"] as? Double {
            let expiry = Date(timeIntervalSince1970: expiresMs / 1000)
            expiryString = String(expiry.timeIntervalSince1970)
            try KeychainStore.save(expiryString!, account: BrokerCredentialKey.webullTokenExpiry)
        } else if let expireTime = tokenResponse["expire_time"] as? String,
                  let expiry = ISO8601DateFormatter().date(from: expireTime) {
            expiryString = String(expiry.timeIntervalSince1970)
            try KeychainStore.save(expiryString!, account: BrokerCredentialKey.webullTokenExpiry)
        } else {
            let fallback = Date().addingTimeInterval(15 * 24 * 3600)
            expiryString = String(fallback.timeIntervalSince1970)
            try KeychainStore.save(expiryString!, account: BrokerCredentialKey.webullTokenExpiry)
        }
        BrokerTokenCache.setWebull(
            access: token,
            expiry: expiryString,
            accountID: BrokerTokenCache.webullAccountID()
        )
    }

    private func fetchPrimaryAccountID(appKey: String, appSecret: String, accessToken: String) async throws -> String {
        let path = "/openapi/account/list"
        let (data, response) = try await signedRequest(
            method: "GET",
            path: path,
            query: [:],
            body: nil,
            appKey: appKey,
            appSecret: appSecret,
            accessToken: accessToken
        )
        try validateHTTP(response: response, data: data)

        let json = try parseJSONObject(data)
        let accounts: [[String: Any]]
        if let list = json["accounts"] as? [[String: Any]] {
            accounts = list
        } else if let list = json["data"] as? [[String: Any]] {
            accounts = list
        } else if let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            accounts = list
        } else {
            throw WebullBrokerError.invalidResponse
        }

        guard let first = accounts.first,
              let accountID = first["account_id"] as? String ?? first["accountId"] as? String else {
            throw WebullBrokerError.invalidResponse
        }
        return accountID
    }

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw WebullBrokerError.invalidResponse
        }
        if let nested = json["data"] as? [String: Any] {
            return nested
        }
        return json
    }

    private func signedRequest(
        method: String,
        path: String,
        query: [String: String],
        body: Data?,
        appKey: String,
        appSecret: String,
        accessToken: String
    ) async throws -> (Data, URLResponse) {
        let timestamp = Self.utcTimestamp()
        let nonce = UUID().uuidString.replacingOccurrences(of: "-", with: "")
        let bodyString = body.flatMap { String(data: $0, encoding: .utf8) }
        let signature = Self.generateSignature(
            path: path,
            query: query,
            bodyString: bodyString,
            appKey: appKey,
            appSecret: appSecret,
            host: host,
            timestamp: timestamp,
            nonce: nonce
        )

        var components = URLComponents()
        components.scheme = "https"
        components.host = host
        components.path = path
        if !query.isEmpty {
            components.queryItems = query.map { URLQueryItem(name: $0.key, value: $0.value) }
        }

        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue(appKey, forHTTPHeaderField: "x-app-key")
        request.setValue(timestamp, forHTTPHeaderField: "x-timestamp")
        request.setValue(signature, forHTTPHeaderField: "x-signature")
        request.setValue("HMAC-SHA1", forHTTPHeaderField: "x-signature-algorithm")
        request.setValue("1.0", forHTTPHeaderField: "x-signature-version")
        request.setValue(nonce, forHTTPHeaderField: "x-signature-nonce")
        request.setValue("v2", forHTTPHeaderField: "x-version")
        request.setValue(accessToken, forHTTPHeaderField: "x-access-token")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }

        return try await session.data(for: request)
    }

    static func generateSignature(
        path: String,
        query: [String: String],
        bodyString: String?,
        appKey: String,
        appSecret: String,
        host: String,
        timestamp: String,
        nonce: String
    ) -> String {
        var params: [String: String] = query
        params["host"] = host
        params["x-app-key"] = appKey
        params["x-signature-algorithm"] = "HMAC-SHA1"
        params["x-signature-nonce"] = nonce
        params["x-signature-version"] = "1.0"
        params["x-timestamp"] = timestamp

        let str1 = params.keys.sorted().map { "\($0)=\(params[$0] ?? "")" }.joined(separator: "&")
        let str3: String
        if let bodyString, !bodyString.isEmpty {
            let md5 = Insecure.MD5.hash(data: Data(bodyString.utf8))
            let str2 = md5.map { String(format: "%02X", $0) }.joined()
            str3 = "\(path)&\(str1)&\(str2)"
        } else {
            str3 = "\(path)&\(str1)"
        }

        let encoded = fullyPercentEncode(str3)
        let key = SymmetricKey(data: Data("\(appSecret)&".utf8))
        let mac = HMAC<Insecure.SHA1>.authenticationCode(for: Data(encoded.utf8), using: key)
        return Data(mac).base64EncodedString()
    }

    private static func fullyPercentEncode(_ value: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-._~")
        return value.addingPercentEncoding(withAllowedCharacters: allowed.inverted) ?? value
    }

    private static func utcTimestamp() -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return formatter.string(from: Date())
    }

    private func validateTokenHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw WebullBrokerError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["message"] as? String {
                    throw WebullBrokerError.apiError(message)
                }
                if let code = json["error_code"] as? String {
                    throw WebullBrokerError.apiError(code.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            }
            if http.statusCode == 401 {
                throw WebullBrokerError.apiError("Webull rejected the app credentials. Check App Key and Secret in this build.")
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WebullBrokerError.apiError(message)
        }
    }

    private func validateHTTP(response: URLResponse, data: Data) throws {
        guard let http = response as? HTTPURLResponse else { throw WebullBrokerError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            if http.statusCode == 401 {
                disconnect()
                throw WebullBrokerError.sessionExpired
            }
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] {
                if let message = json["message"] as? String {
                    throw WebullBrokerError.apiError(message)
                }
                if let code = json["error_code"] as? String {
                    throw WebullBrokerError.apiError(code.replacingOccurrences(of: "_", with: " ").capitalized)
                }
            }
            let message = String(data: data, encoding: .utf8) ?? "HTTP \(http.statusCode)"
            throw WebullBrokerError.apiError(message)
        }
    }
}
