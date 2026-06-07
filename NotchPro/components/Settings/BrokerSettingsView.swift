//
//  BrokerSettingsView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct IntegrationsSettings: View {
    @Default(.showPortfolioGlance) var showPortfolioGlance
    @Default(.enablePortfolioInsights) var enablePortfolioInsights
    @ObservedObject private var portfolio = PortfolioManager.shared

    @State private var schwabManualURL = ""
    @State private var groqAPIKey = ""
    @State private var statusMessage: String?

    private let config = BrokerConfig.shared

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                Text("Integrations")
                    .font(.largeTitle.weight(.bold))
                    .padding(.horizontal, 28)
                    .padding(.top, 24)
                    .padding(.bottom, 12)

                VStack(alignment: .leading, spacing: 4) {
                    SettingsSectionCard(
                        title: "Portfolio",
                        footer: "Link your brokerage accounts once. Tokens stay in the macOS Keychain on this Mac only."
                    ) {
                        Defaults.Toggle(key: .showPortfolioGlance) {
                            Text("Show portfolio in notch")
                        }
                        .onChange(of: showPortfolioGlance) {
                            if showPortfolioGlance {
                                PortfolioManager.shared.startIfEnabled()
                            } else {
                                PortfolioManager.shared.stop()
                            }
                        }

                        if showPortfolioGlance, portfolio.hasAnyConnection {
                            Button("Refresh positions") {
                                Task { await portfolio.refresh() }
                            }
                            .buttonStyle(.bordered)
                            .controlSize(.small)
                        }
                    }

                    schwabSection
                    webullSection
                    portfolioInsightsSection

                    if let statusMessage {
                        Text(statusMessage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 28)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(nsColor: .windowBackgroundColor))
        .onAppear {
            portfolio.refreshConnectionStatesFromKeychain()
            groqAPIKey = KeychainStore.load(account: IntegrationCredentialKey.groqAPIKey) ?? ""
        }
    }

    private var portfolioInsightsSection: some View {
        SettingsSectionCard(
            title: "Portfolio AI insights",
            footer: PortfolioInsightsManager.shared.usesBuiltInAI
                ? "Built-in AI is included for you and your friends — no setup needed. News comes from Yahoo Finance RSS."
                : "Add an optional Groq API key below, or ask the app owner to enable the shared insights service."
        ) {
            Defaults.Toggle(key: .enablePortfolioInsights) {
                Text("Enable AI portfolio insights")
            }

            if PortfolioInsightsManager.shared.usesBuiltInAI {
                Label("Built-in AI active", systemImage: "sparkles")
                    .font(.caption)
                    .foregroundStyle(.green)
            }

            DisclosureGroup("Advanced: use your own Groq key") {
                SecureField("Groq API key (optional)", text: $groqAPIKey)
                    .textFieldStyle(.roundedBorder)

                HStack(spacing: 10) {
                    Button("Save API key") {
                        do {
                            try PortfolioInsightsManager.shared.saveAPIKey(groqAPIKey)
                            statusMessage = "Groq API key saved."
                        } catch {
                            statusMessage = error.localizedDescription
                        }
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)

                    if PortfolioInsightsManager.shared.hasAPIKey {
                        Button("Remove key", role: .destructive) {
                            PortfolioInsightsManager.shared.clearAPIKey()
                            groqAPIKey = ""
                            statusMessage = "Groq API key removed."
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                    }
                }
            }
            .font(.caption)
        }
    }

    private var schwabSection: some View {
        SettingsSectionCard(
            title: "Charles Schwab",
            footer: config.isSchwabConfigured
                ? "Sign in with your Schwab account in the browser. If the redirect page says connection refused, expand “Paste redirect URL manually” and paste the full https://127.0.0.1:8765/?code=… URL from the address bar."
                : nil
        ) {
            brokerHeader(
                title: "Charles Schwab",
                icon: "building.columns.fill",
                tint: .blue,
                connected: SchwabBrokerService.shared.isConnected,
                state: portfolio.schwabState
            )

            if !config.isSchwabConfigured {
                Label("Schwab not available in this build", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                stateMessage(portfolio.schwabState)
                connectButton(
                    "Connect Schwab",
                    isConnecting: portfolio.schwabState == .connecting
                ) {
                    await portfolio.connectSchwab()
                    statusMessage = portfolio.lastError ?? "Schwab connected."
                }
                if SchwabBrokerService.shared.isConnected {
                    disconnectButton("Disconnect Schwab") {
                        portfolio.disconnectSchwab()
                        statusMessage = "Schwab disconnected."
                    }
                }
                DisclosureGroup("Paste redirect URL manually (if browser shows connection refused)") {
                    TextField("https://127.0.0.1:8765/?code=…", text: $schwabManualURL)
                        .textFieldStyle(.roundedBorder)
                    Button("Complete connection") {
                        Task {
                            await portfolio.connectSchwab(manualRedirectURL: schwabManualURL)
                            statusMessage = portfolio.lastError ?? "Schwab connected."
                        }
                    }
                    .disabled(schwabManualURL.isEmpty)
                }
                .font(.caption)
            }
        }
    }

    private var webullSection: some View {
        SettingsSectionCard(
            title: "Webull",
            footer: config.isWebullConfigured
                ? "Approve the SMS code in Webull → Menu → Messages → OpenAPI Notifications. Codes expire in about 5 minutes — tap Connect again if yours expired."
                : nil
        ) {
            brokerHeader(
                title: "Webull",
                icon: "chart.bar.fill",
                tint: .cyan,
                connected: WebullBrokerService.shared.isConnected,
                state: portfolio.webullState
            )

            if !config.isWebullConfigured {
                Label("Webull not available in this build", systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.orange)
            } else {
                stateMessage(portfolio.webullState)
                connectButton(
                    "Connect Webull",
                    isConnecting: portfolio.webullState == .connecting
                ) {
                    await portfolio.connectWebull()
                    statusMessage = portfolio.lastError ?? "Webull connected."
                }
                if case .awaitingVerification = portfolio.webullState {
                    Button("Retry connection") {
                        Task {
                            await portfolio.connectWebull()
                            statusMessage = portfolio.lastError ?? "Webull connected."
                        }
                    }
                    .buttonStyle(.bordered)
                }
                if WebullBrokerService.shared.isConnected {
                    disconnectButton("Disconnect Webull") {
                        portfolio.disconnectWebull()
                        statusMessage = "Webull disconnected."
                    }
                }
            }
        }
    }

    private func brokerHeader(
        title: String,
        icon: String,
        tint: Color,
        connected: Bool,
        state: BrokerConnectionState
    ) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(tint.opacity(0.15))
                    .frame(width: 36, height: 36)
                Image(systemName: icon)
                    .foregroundStyle(tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.headline)
                connectionBadge(connected: connected, state: state)
            }
            Spacer(minLength: 0)
        }
    }

    @ViewBuilder
    private func connectButton(
        _ title: String,
        isConnecting: Bool,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Label(title, systemImage: "link")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.borderedProminent)
        .controlSize(.large)
        .disabled(isConnecting)
    }

    @ViewBuilder
    private func disconnectButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(title, role: .destructive, action: action)
            .buttonStyle(.bordered)
            .controlSize(.small)
    }

    @ViewBuilder
    private func connectionBadge(connected: Bool, state: BrokerConnectionState) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 7, height: 7)
            Text(connected ? "Connected" : statusLabel(for: state))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func stateMessage(_ state: BrokerConnectionState) -> some View {
        switch state {
        case .connecting:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Connecting…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .awaitingVerification(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.orange)
        case .error(let message):
            Text(message)
                .font(.caption)
                .foregroundStyle(.red)
        default:
            EmptyView()
        }
    }

    private func statusLabel(for state: BrokerConnectionState) -> String {
        switch state {
        case .connecting: return "Connecting…"
        case .awaitingVerification: return "Awaiting SMS approval"
        case .error: return "Error"
        default: return "Not connected"
        }
    }
}
