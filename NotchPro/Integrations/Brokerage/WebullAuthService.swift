//
//  WebullAuthService.swift
//  NotchPro
//

import CryptoKit
import Foundation
import NotchProCore

@MainActor
final class WebullAuthService {
    static let shared = WebullAuthService()

    private let host = "api.webull.com"

    private init() {}

    func connect(onPendingVerification: (() -> Void)? = nil) async throws -> BrokerTokenRecord {
        guard BrokerConfig.shared.isWebullConfigured else {
            throw BrokerageConnectionError.notConfigured(.webull)
        }

        let config = BrokerConfig.shared
        let tokenResponse = try await createToken(appKey: config.webullAppKey, appSecret: config.webullAppSecret)
        let status = (tokenResponse["status"] as? String) ?? ""

        if status.uppercased() == "NORMAL", let token = tokenResponse["token"] as? String {
            return try record(from: tokenResponse, token: token)
        }

        if status.uppercased() == "PENDING", let pendingToken = tokenResponse["token"] as? String {
            onPendingVerification?()
            return try await pollUntilVerified(pendingToken: pendingToken)
        }

        throw BrokerageConnectionError.providerMessage("Token status: \(status)", debugCode: "webull_token_status")
    }

    func validAccessToken() async throws -> String {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        let record = try KeychainTokenStore.load(provider: .webull)
        if record.isAccessValid(buffer: 120) {
            return record.accessToken
        }
        throw BrokerageConnectionError.sessionExpired
    }

    func accountID(for accessToken: String) async throws -> String {
        if let record = try? KeychainTokenStore.load(provider: .webull),
           record.providerUserID != "default" {
            return record.providerUserID
        }

        let config = BrokerConfig.shared
        let (data, status) = try await signedDataRequest(
            method: "GET",
            path: "/openapi/account/list",
            query: [:],
            body: nil,
            appKey: config.webullAppKey,
            appSecret: config.webullAppSecret,
            accessToken: accessToken
        )
        try validateHTTP(status: status, data: data)

        let json = try parseJSONObject(data)
        let accounts: [[String: Any]]
        if let list = json["accounts"] as? [[String: Any]] {
            accounts = list
        } else if let list = json["data"] as? [[String: Any]] {
            accounts = list
        } else if let list = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] {
            accounts = list
        } else {
            throw BrokerageConnectionError.providerMessage("Unexpected response from Webull.", debugCode: "webull_accounts")
        }

        guard let first = accounts.first,
              let accountID = first["account_id"] as? String ?? first["accountId"] as? String else {
            throw BrokerageConnectionError.providerMessage("Unexpected response from Webull.", debugCode: "webull_account_id")
        }
        return accountID
    }

    func signedDataRequest(
        method: String,
        path: String,
        query: [String: String],
        body: Data?,
        appKey: String,
        appSecret: String,
        accessToken: String
    ) async throws -> (Data, Int) {
        let request = try buildSignedRequest(
            method: method,
            path: path,
            query: query,
            body: body,
            appKey: appKey,
            appSecret: appSecret,
            accessToken: accessToken
        )
        let response = try await BrokerHTTPClient.data(for: request)
        return (response.data, response.statusCode)
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

    // MARK: - Private

    private func record(from tokenResponse: [String: Any], token: String) throws -> BrokerTokenRecord {
        let expiresAt: Date
        let refreshExpiresAt = Date().addingTimeInterval(15 * 24 * 3600)

        if let expiresMs = tokenResponse["expires"] as? Int {
            expiresAt = Date(timeIntervalSince1970: Double(expiresMs) / 1000)
        } else if let expiresMs = tokenResponse["expires"] as? Double {
            expiresAt = Date(timeIntervalSince1970: expiresMs / 1000)
        } else if let expireTime = tokenResponse["expire_time"] as? String,
                  let expiry = ISO8601DateFormatter().date(from: expireTime) {
            expiresAt = expiry
        } else {
            expiresAt = Date().addingTimeInterval(30 * 60)
        }

        return BrokerTokenRecord(
            accessToken: token,
            refreshToken: tokenResponse["refresh_token"] as? String,
            expiresAt: expiresAt,
            refreshExpiresAt: refreshExpiresAt,
            providerUserID: "default",
            scopes: nil
        )
    }

    private func pollUntilVerified(pendingToken: String) async throws -> BrokerTokenRecord {
        let config = BrokerConfig.shared
        var activePendingToken = pendingToken
        var smsRetries = 0

        for _ in 0..<60 {
            try await Task.sleep(for: .seconds(5))
            let statusResponse = try await checkToken(
                appKey: config.webullAppKey,
                appSecret: config.webullAppSecret,
                token: activePendingToken
            )
            let status = (statusResponse["status"] as? String) ?? ""
            if status.uppercased() == "NORMAL", let token = statusResponse["token"] as? String {
                return try record(from: statusResponse, token: token)
            }
            if status.uppercased() == "EXPIRED" || status.uppercased() == "INVALID" {
                guard smsRetries < 2 else { throw BrokerageConnectionError.authorizationExpired }
                smsRetries += 1
                let fresh = try await createToken(appKey: config.webullAppKey, appSecret: config.webullAppSecret)
                let freshStatus = (fresh["status"] as? String) ?? ""
                if freshStatus.uppercased() == "NORMAL", let token = fresh["token"] as? String {
                    return try record(from: fresh, token: token)
                }
                if freshStatus.uppercased() == "PENDING", let newPending = fresh["token"] as? String {
                    activePendingToken = newPending
                    continue
                }
                throw BrokerageConnectionError.authorizationExpired
            }
        }
        throw BrokerageConnectionError.providerMessage(
            "Check the Webull app and enter the SMS code to finish connecting.",
            debugCode: "webull_pending"
        )
    }

    private func createToken(appKey: String, appSecret: String) async throws -> [String: Any] {
        let (data, status) = try await signedTokenRequest(
            method: "POST",
            path: "/openapi/auth/token/create",
            body: "{}".data(using: .utf8),
            appKey: appKey,
            appSecret: appSecret
        )
        try validateTokenHTTP(status: status, data: data)
        return try parseJSONObject(data)
    }

    private func checkToken(appKey: String, appSecret: String, token: String) async throws -> [String: Any] {
        let body = try JSONSerialization.data(withJSONObject: ["token": token])
        let (data, status) = try await signedTokenRequest(
            method: "POST",
            path: "/openapi/auth/token/check",
            body: body,
            appKey: appKey,
            appSecret: appSecret
        )
        try validateTokenHTTP(status: status, data: data)
        return try parseJSONObject(data)
    }

    private func signedTokenRequest(
        method: String,
        path: String,
        body: Data?,
        appKey: String,
        appSecret: String
    ) async throws -> (Data, Int) {
        let request = try buildSignedRequest(
            method: method,
            path: path,
            query: [:],
            body: body,
            appKey: appKey,
            appSecret: appSecret,
            accessToken: nil
        )
        let response = try await BrokerHTTPClient.data(for: request)
        return (response.data, response.statusCode)
    }

    private func buildSignedRequest(
        method: String,
        path: String,
        query: [String: String],
        body: Data?,
        appKey: String,
        appSecret: String,
        accessToken: String?
    ) throws -> URLRequest {
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
        if let accessToken {
            request.setValue(accessToken, forHTTPHeaderField: "x-access-token")
        }
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = body
        }
        return request
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

    private func parseJSONObject(_ data: Data) throws -> [String: Any] {
        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw BrokerageConnectionError.providerMessage("Unexpected response from Webull.", debugCode: "webull_json")
        }
        if let nested = json["data"] as? [String: Any] {
            return nested
        }
        return json
    }

    private func validateTokenHTTP(status: Int, data: Data) throws {
        guard (200...299).contains(status) else {
            if let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
               let message = json["message"] as? String {
                throw BrokerageConnectionError.providerMessage(message, debugCode: "webull_token_http")
            }
            throw BrokerageConnectionError.apiHTTP(status: status, debugCode: "webull_token_http")
        }
    }

    private func validateHTTP(status: Int, data: Data) throws {
        guard (200...299).contains(status) else {
            if status == 401 {
                throw BrokerageConnectionError.sessionExpired
            }
            throw BrokerageConnectionError.apiHTTP(status: status, debugCode: "webull_api")
        }
    }
}
