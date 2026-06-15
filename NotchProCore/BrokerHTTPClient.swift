//
//  BrokerHTTPClient.swift
//  NotchProCore
//

import Foundation

public struct BrokerHTTPResponse: Sendable {
    public let statusCode: Int
    public let data: Data
    public let correlationID: String

    public init(statusCode: Int, data: Data, correlationID: String) {
        self.statusCode = statusCode
        self.data = data
        self.correlationID = correlationID
    }
}

public enum BrokerHTTPClient {
    /// Optional hook for app-level diagnostics (status code, correlation ID).
    public static var onResponse: (@Sendable (Int, String) -> Void)?

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 25
        config.timeoutIntervalForResource = 40
        return URLSession(configuration: config)
    }()

    public static func postJSON(
        url: URL,
        body: [String: Any],
        headers: [String: String] = [:],
        maxAttempts: Int = 3
    ) async throws -> BrokerHTTPResponse {
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        headers.forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return try await perform(request, maxAttempts: maxAttempts)
    }

    public static func data(
        for request: URLRequest,
        maxAttempts: Int = 3
    ) async throws -> BrokerHTTPResponse {
        try await perform(request, maxAttempts: maxAttempts)
    }

    private static func perform(_ request: URLRequest, maxAttempts: Int) async throws -> BrokerHTTPResponse {
        var attempt = 0
        var delay: UInt64 = 400_000_000

        while true {
            attempt += 1
            let correlationID = UUID().uuidString
            var loggedRequest = request
            loggedRequest.setValue(correlationID, forHTTPHeaderField: "X-NotchPro-Correlation-ID")

            do {
                let (data, response) = try await session.data(for: loggedRequest)
                guard let http = response as? HTTPURLResponse else {
                    throw BrokerageConnectionError.networkUnavailable
                }

                onResponse?(http.statusCode, correlationID)

                if (200...299).contains(http.statusCode) {
                    return BrokerHTTPResponse(statusCode: http.statusCode, data: data, correlationID: correlationID)
                }

                let oauthError = parseOAuthError(data: data)
                if let oauthError {
                    throw oauthError
                }

                if [429, 500, 502, 503, 504].contains(http.statusCode), attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 4_000_000_000)
                    continue
                }

                throw BrokerageConnectionError.apiHTTP(status: http.statusCode, debugCode: "broker_http")
            } catch let error as BrokerageConnectionError {
                if error.isRetryable, attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 4_000_000_000)
                    continue
                }
                throw error
            } catch {
                if attempt < maxAttempts {
                    try await Task.sleep(nanoseconds: delay)
                    delay = min(delay * 2, 4_000_000_000)
                    continue
                }
                throw BrokerageConnectionError.networkUnavailable
            }
        }
    }

    private static func parseOAuthError(data: Data) -> BrokerageConnectionError? {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        let code = (json["error"] as? String) ?? (json["error_code"] as? String) ?? ""
        switch code {
        case "invalid_grant":
            return .invalidGrant
        case "invalid_client":
            return .invalidClient
        case "invalid_redirect_uri":
            return .invalidRedirect
        default:
            if let message = json["error_description"] as? String ?? json["message"] as? String, !message.isEmpty {
                return .providerMessage(message, debugCode: code.isEmpty ? "provider_error" : code)
            }
            return nil
        }
    }
}
