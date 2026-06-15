//
//  BrokerageConnectionError.swift
//  NotchProCore
//

import Foundation

public enum BrokerageProvider: String, CaseIterable, Codable, Sendable {
    case schwab
    case webull

    public var displayName: String {
        switch self {
        case .schwab: return "Schwab"
        case .webull: return "Webull"
        }
    }
}

public enum BrokerageConnectionPhase: Equatable, Sendable {
    case disconnected
    case authorizing
    case exchangingCode
    case connected
    case refreshingToken
    case awaitingVerification(String)
    case expired
    case failed(String)
}

public enum BrokerageConnectionError: LocalizedError, Equatable, Sendable {
    case loginCancelled
    case authorizationExpired
    case codeExchangeFailed
    case sessionExpired
    case networkUnavailable
    case rateLimited
    case providerUnavailable
    case invalidRedirect
    case invalidGrant
    case invalidClient
    case missingCode
    case stateMismatch
    case callbackTimeout
    case keychain(KeychainTokenError)
    case notConfigured(BrokerageProvider)
    case providerMessage(String, debugCode: String)
    case apiHTTP(status: Int, debugCode: String)

    public var errorDescription: String? {
        switch self {
        case .loginCancelled:
            return "Login was cancelled."
        case .authorizationExpired:
            return "Authorization expired. Please try connecting again."
        case .codeExchangeFailed:
            return "Could not exchange login code. Check redirect URL/provider configuration."
        case .sessionExpired:
            return "Session expired. Please reconnect."
        case .networkUnavailable:
            return "Network error. Check internet/VPN/firewall."
        case .rateLimited:
            return "Provider rate limit hit. Try again shortly."
        case .providerUnavailable:
            return "Brokerage service temporarily unavailable."
        case .invalidRedirect:
            return "Could not exchange login code. Check redirect URL/provider configuration."
        case .invalidGrant:
            return "Authorization expired. Please try connecting again."
        case .invalidClient:
            return "Could not exchange login code. Check redirect URL/provider configuration."
        case .missingCode:
            return "Could not exchange login code. Check redirect URL/provider configuration."
        case .stateMismatch:
            return "Authorization expired. Please try connecting again."
        case .callbackTimeout:
            return "Authorization expired. Please try connecting again."
        case .keychain(let error):
            return error.localizedDescription
        case .notConfigured(let provider):
            return "\(provider.displayName) isn't set up in this build of NotchPro yet."
        case .providerMessage(let message, _):
            return message
        case .apiHTTP(let status, _):
            if (500...599).contains(status) {
                return "Brokerage service temporarily unavailable."
            }
            return "Connection failed (HTTP \(status))."
        }
    }

    public var debugCode: String {
        switch self {
        case .loginCancelled: return "auth_cancelled"
        case .authorizationExpired: return "auth_expired"
        case .codeExchangeFailed: return "code_exchange_failed"
        case .sessionExpired: return "session_expired"
        case .networkUnavailable: return "network_unavailable"
        case .rateLimited: return "rate_limited"
        case .providerUnavailable: return "provider_unavailable"
        case .invalidRedirect: return "invalid_redirect_uri"
        case .invalidGrant: return "invalid_grant"
        case .invalidClient: return "invalid_client"
        case .missingCode: return "missing_code"
        case .stateMismatch: return "state_mismatch"
        case .callbackTimeout: return "callback_timeout"
        case .keychain(let e): return "keychain_\(e.debugCode)"
        case .notConfigured: return "not_configured"
        case .providerMessage(_, let code): return code
        case .apiHTTP(let status, let code): return "\(code)_http_\(status)"
        }
    }

    public var isRetryable: Bool {
        switch self {
        case .rateLimited, .providerUnavailable, .networkUnavailable:
            return true
        case .apiHTTP(let status, _) where (500...599).contains(status):
            return true
        default:
            return false
        }
    }

    public var requiresReauthorization: Bool {
        switch self {
        case .invalidGrant, .sessionExpired, .authorizationExpired, .invalidClient:
            return true
        default:
            return false
        }
    }
}
