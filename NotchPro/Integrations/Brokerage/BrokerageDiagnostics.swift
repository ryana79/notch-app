//
//  BrokerageDiagnostics.swift
//  NotchPro
//

import Combine
import Foundation
import NotchProCore

@MainActor
final class BrokerageDiagnostics: ObservableObject {
    static let shared = BrokerageDiagnostics()

    @Published private(set) var lastHTTPStatus: Int?
    @Published private(set) var lastCorrelationID: String?
    @Published private(set) var lastProviderErrorCode: String?
    @Published private(set) var lastKeychainResult: String?
    @Published private(set) var schwabAccessExpiry: Date?
    @Published private(set) var schwabRefreshExpiry: Date?
    @Published private(set) var webullAccessExpiry: Date?
    @Published private(set) var webullRefreshExpiry: Date?
    @Published private(set) var lastConnectionState: [BrokerageProvider: BrokerageConnectionPhase] = [:]

    private init() {}

    static func wireHTTPLogging() {
        BrokerHTTPClient.onResponse = { status, correlationID in
            Task { @MainActor in
                BrokerageDiagnostics.shared.record(
                    status: status,
                    correlationID: correlationID,
                    errorCode: nil
                )
            }
        }
    }

    func record(status: Int, correlationID: String, errorCode: String?) {
        lastHTTPStatus = status
        lastCorrelationID = correlationID
        lastProviderErrorCode = errorCode
    }

    func recordKeychain(_ message: String) {
        lastKeychainResult = message
    }

    func updateTokenExpiries(schwab: BrokerTokenRecord?, webull: BrokerTokenRecord?) {
        schwabAccessExpiry = schwab?.expiresAt
        schwabRefreshExpiry = schwab?.refreshExpiresAt
        webullAccessExpiry = webull?.expiresAt
        webullRefreshExpiry = webull?.refreshExpiresAt
    }

    func setPhase(_ phase: BrokerageConnectionPhase, provider: BrokerageProvider) {
        lastConnectionState[provider] = phase
    }
}
