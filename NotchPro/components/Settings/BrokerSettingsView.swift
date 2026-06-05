//
//  BrokerSettingsView.swift
//  NotchPro
//

import Defaults
import SwiftUI

struct IntegrationsSettings: View {
    @Default(.showPortfolioGlance) var showPortfolioGlance
    @ObservedObject private var portfolio = PortfolioManager.shared

    @State private var schwabManualURL = ""
    @State private var statusMessage: String?

    private let config = BrokerConfig.shared

    var body: some View {
        Form {
            Section {
                Defaults.Toggle(key: .showPortfolioGlance) {
                    Text("Portfolio glance in notch")
                }
                .onChange(of: showPortfolioGlance) {
                    if showPortfolioGlance {
                        PortfolioManager.shared.startIfEnabled()
                    } else {
                        PortfolioManager.shared.stop()
                    }
                }

                if showPortfolioGlance, portfolio.hasAnyConnection {
                    Button("Refresh now") {
                        Task { await portfolio.refresh() }
                    }
                }
            } header: {
                Text("Portfolio")
            } footer: {
                Text("Link your brokerage accounts once. Your login tokens stay in the macOS Keychain on this Mac only.")
            }

            schwabSection
            webullSection

            if let statusMessage {
                Section {
                    Text(statusMessage)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .navigationTitle("Integrations")
        .onAppear {
            portfolio.updateConnectionStates()
        }
    }

    private var schwabSection: some View {
        Section {
            if !config.isSchwabConfigured {
                Label("Schwab not available in this build", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                connectionStatusRow(
                    connected: SchwabBrokerService.shared.isConnected,
                    state: portfolio.schwabState
                )

                Button {
                    Task {
                        await portfolio.connectSchwab()
                        statusMessage = portfolio.lastError ?? "Schwab connected."
                    }
                } label: {
                    Label("Connect Schwab", systemImage: "link")
                }
                .disabled(!config.isSchwabConfigured || portfolio.schwabState == .connecting)

                if SchwabBrokerService.shared.isConnected {
                    Button("Disconnect Schwab", role: .destructive) {
                        portfolio.disconnectSchwab()
                        statusMessage = "Schwab disconnected."
                    }
                }

                DisclosureGroup("Trouble connecting? Paste redirect URL") {
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
            }
        } header: {
            Text("Charles Schwab")
        } footer: {
            if config.isSchwabConfigured {
                Text("Sign in with your Schwab account in the browser. You may need to reconnect about once a week.")
            }
        }
    }

    private var webullSection: some View {
        Section {
            if !config.isWebullConfigured {
                Label("Webull not available in this build", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
            } else {
                connectionStatusRow(
                    connected: WebullBrokerService.shared.isConnected,
                    state: portfolio.webullState
                )

                Button {
                    Task {
                        await portfolio.connectWebull()
                        statusMessage = portfolio.lastError ?? "Webull connected."
                    }
                } label: {
                    Label("Connect Webull", systemImage: "link")
                }
                .disabled(!config.isWebullConfigured || portfolio.webullState == .connecting)

                if case .awaitingVerification = portfolio.webullState {
                    Button("Retry Webull connection") {
                        Task {
                            await portfolio.connectWebull()
                            statusMessage = portfolio.lastError ?? "Webull connected."
                        }
                    }
                }

                if WebullBrokerService.shared.isConnected {
                    Button("Disconnect Webull", role: .destructive) {
                        portfolio.disconnectWebull()
                        statusMessage = "Webull disconnected."
                    }
                }
            }
        } header: {
            Text("Webull")
        } footer: {
            if config.isWebullConfigured {
                Text("If prompted, approve the SMS code in the Webull app under Menu → Messages → OpenAPI Notifications.")
            }
        }
    }

    @ViewBuilder
    private func connectionStatusRow(connected: Bool, state: BrokerConnectionState) -> some View {
        HStack(spacing: 8) {
            Circle()
                .fill(connected ? Color.green : Color.orange)
                .frame(width: 8, height: 8)
            Text(connected ? "Connected" : "Not connected")
                .foregroundStyle(.secondary)
            Spacer()
        }

        switch state {
        case .connecting:
            ProgressView("Connecting…")
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
}
