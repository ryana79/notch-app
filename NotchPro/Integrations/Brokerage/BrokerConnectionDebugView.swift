//
//  BrokerConnectionDebugView.swift
//  NotchPro
//

import AppKit
import SwiftUI

#if DEBUG
struct BrokerConnectionDebugView: View {
    @ObservedObject private var diagnostics = BrokerageDiagnostics.shared
    @ObservedObject private var manager = BrokerageConnectionManager.shared

    var body: some View {
        Form {
            Section("Environment") {
                LabeledContent("macOS", value: ProcessInfo.processInfo.operatingSystemVersionString)
                LabeledContent("App", value: appVersion)
                LabeledContent("Bundle ID", value: Bundle.main.bundleIdentifier ?? "—")
                LabeledContent("Sandbox", value: "true")
            }

            Section("Callbacks") {
                LabeledContent("Schwab redirect", value: SchwabAuthService.redirectURI)
                LabeledContent("Custom scheme", value: SchwabAuthService.customSchemeRedirectURI)
            }

            Section("Connection state") {
                LabeledContent("Schwab", value: "\(manager.schwabPhase)")
                LabeledContent("Webull", value: "\(manager.webullPhase)")
                LabeledContent("Auth in progress", value: manager.authorizationInProgress ? "yes" : "no")
            }

            Section("Token expiry (no secrets)") {
                LabeledContent("Schwab access", value: fmt(diagnostics.schwabAccessExpiry))
                LabeledContent("Schwab refresh", value: fmt(diagnostics.schwabRefreshExpiry))
                LabeledContent("Webull access", value: fmt(diagnostics.webullAccessExpiry))
                LabeledContent("Webull refresh", value: fmt(diagnostics.webullRefreshExpiry))
            }

            Section("Last request") {
                LabeledContent("HTTP status", value: diagnostics.lastHTTPStatus.map(String.init) ?? "—")
                LabeledContent("Correlation ID", value: diagnostics.lastCorrelationID ?? "—")
                LabeledContent("Provider error", value: diagnostics.lastProviderErrorCode ?? "—")
                LabeledContent("Keychain", value: diagnostics.lastKeychainResult ?? "—")
            }
        }
        .formStyle(.grouped)
        .frame(minWidth: 520, minHeight: 420)
    }

    private var appVersion: String {
        let version = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        return "\(version) (\(build))"
    }

    private func fmt(_ date: Date?) -> String {
        guard let date else { return "—" }
        return date.formatted(date: .abbreviated, time: .standard)
    }
}
#endif
