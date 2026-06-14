//
//  BrokerageConnectionManager.swift
//  NotchPro
//

import Combine
import Foundation

@MainActor
final class BrokerageConnectionManager: ObservableObject {
    static let shared = BrokerageConnectionManager()

    @Published private(set) var schwabPhase: BrokerageConnectionPhase = .disconnected
    @Published private(set) var webullPhase: BrokerageConnectionPhase = .disconnected
    @Published private(set) var lastError: String?
    @Published private(set) var authorizationInProgress = false

    private init() {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        refreshPhasesFromStorage()
    }

    var hasAnyConnection: Bool {
        if case .connected = schwabPhase { return true }
        if case .connected = webullPhase { return true }
        return false
    }

    func refreshPhasesFromStorage() {
        if (try? KeychainTokenStore.load(provider: .schwab)) != nil {
            schwabPhase = .connected
            BrokerConnectionCache.setSchwabConnected(true)
        } else {
            schwabPhase = .disconnected
            BrokerConnectionCache.setSchwabConnected(false)
        }

        if (try? KeychainTokenStore.load(provider: .webull)) != nil {
            webullPhase = .connected
            BrokerConnectionCache.setWebullConnected(true)
        } else {
            webullPhase = .disconnected
            BrokerConnectionCache.setWebullConnected(false)
        }

        BrokerageDiagnostics.shared.updateTokenExpiries(
            schwab: try? KeychainTokenStore.load(provider: .schwab),
            webull: try? KeychainTokenStore.load(provider: .webull)
        )
    }

    func connectSchwab() async {
        guard !authorizationInProgress else { return }
        authorizationInProgress = true
        schwabPhase = .authorizing
        lastError = nil
        BrokerageDiagnostics.shared.setPhase(.authorizing, provider: .schwab)

        defer { authorizationInProgress = false }

        do {
            let code = try await SchwabAuthService.shared.authorize()
            schwabPhase = .exchangingCode
            BrokerageDiagnostics.shared.setPhase(.exchangingCode, provider: .schwab)
            let record = try await SchwabAuthService.shared.exchangeCode(code)
            try KeychainTokenStore.save(record, provider: .schwab)
            BrokerTokenCache.applySchwabRecord(record)
            BrokerConnectionCache.setSchwabConnected(true)
            schwabPhase = .connected
            BrokerageDiagnostics.shared.setPhase(.connected, provider: .schwab)
            BrokerageDiagnostics.shared.recordKeychain("schwab_saved")
            BrokerageDiagnostics.shared.updateTokenExpiries(schwab: record, webull: try? KeychainTokenStore.load(provider: .webull))
        } catch let error as BrokerageConnectionError {
            schwabPhase = .failed(error.localizedDescription ?? "Connection failed")
            lastError = error.localizedDescription
            BrokerageDiagnostics.shared.setPhase(.failed(error.debugCode), provider: .schwab)
        } catch {
            let wrapped = BrokerageConnectionError.providerMessage(error.localizedDescription, debugCode: "schwab_unknown")
            schwabPhase = .failed(wrapped.localizedDescription ?? "Connection failed")
            lastError = wrapped.localizedDescription
            BrokerageDiagnostics.shared.setPhase(.failed(wrapped.debugCode), provider: .schwab)
        }
    }

    func connectSchwab(manualRedirectURL: String) async {
        guard !authorizationInProgress else { return }
        authorizationInProgress = true
        schwabPhase = .exchangingCode
        lastError = nil
        defer { authorizationInProgress = false }

        do {
            guard let code = SchwabAuthService.parseAuthorizationCode(from: URL(string: manualRedirectURL.trimmingCharacters(in: .whitespacesAndNewlines)) ?? URL(fileURLWithPath: "/"))
                ?? Self.parseManualCode(manualRedirectURL) else {
                throw BrokerageConnectionError.missingCode
            }
            let record = try await SchwabAuthService.shared.exchangeCode(code)
            try KeychainTokenStore.save(record, provider: .schwab)
            BrokerTokenCache.applySchwabRecord(record)
            BrokerConnectionCache.setSchwabConnected(true)
            schwabPhase = .connected
        } catch let error as BrokerageConnectionError {
            schwabPhase = .failed(error.localizedDescription ?? "Connection failed")
            lastError = error.localizedDescription
        } catch {
            schwabPhase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnectSchwab() {
        KeychainStore.deleteAll(accounts: BrokerCredentialKey.schwabUserTokens)
        KeychainTokenStore.delete(provider: .schwab)
        BrokerTokenCache.clearSchwab()
        BrokerConnectionCache.setSchwabConnected(false)
        schwabPhase = .disconnected
        BrokerageDiagnostics.shared.setPhase(.disconnected, provider: .schwab)
    }

    func connectWebull(onPendingVerification: (() -> Void)? = nil) async {
        guard !authorizationInProgress else { return }
        authorizationInProgress = true
        webullPhase = .authorizing
        lastError = nil
        defer { authorizationInProgress = false }

        do {
            disconnectWebull()
            let record = try await WebullAuthService.shared.connect(onPendingVerification: {
                self.webullPhase = .awaitingVerification("Approve SMS in the Webull app")
                onPendingVerification?()
            })
            let accountID = try await WebullAuthService.shared.accountID(for: record.accessToken)
            var stored = record
            stored.providerUserID = accountID
            try KeychainTokenStore.save(stored, provider: .webull)
            BrokerTokenCache.applyWebullRecord(stored, accountID: accountID)
            BrokerConnectionCache.setWebullConnected(true)
            webullPhase = .connected
            BrokerageDiagnostics.shared.recordKeychain("webull_saved")
            BrokerageDiagnostics.shared.updateTokenExpiries(schwab: try? KeychainTokenStore.load(provider: .schwab), webull: stored)
        } catch let error as BrokerageConnectionError {
            webullPhase = .failed(error.localizedDescription ?? "Connection failed")
            lastError = error.localizedDescription
        } catch {
            webullPhase = .failed(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnectWebull() {
        KeychainStore.deleteAll(accounts: BrokerCredentialKey.webullUserTokens)
        KeychainTokenStore.delete(provider: .webull)
        BrokerTokenCache.clearWebull()
        BrokerConnectionCache.setWebullConnected(false)
        webullPhase = .disconnected
    }

    private static func parseManualCode(_ input: String) -> String? {
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.contains("code="), let url = URL(string: trimmed) {
            return SchwabAuthService.parseAuthorizationCode(from: url)
        }
        if !trimmed.contains("/"), !trimmed.contains("=") { return trimmed }
        return nil
    }
}

extension BrokerageConnectionPhase {
    var isConnected: Bool {
        if case .connected = self { return true }
        return false
    }

    var isBusy: Bool {
        switch self {
        case .authorizing, .exchangingCode, .refreshingToken, .awaitingVerification:
            return true
        default:
            return false
        }
    }
}
