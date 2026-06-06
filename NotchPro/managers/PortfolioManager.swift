//
//  PortfolioManager.swift
//  NotchPro
//

import Combine
import Defaults
import Foundation

@MainActor
final class PortfolioManager: ObservableObject {
    static let shared = PortfolioManager()

    @Published private(set) var snapshot: PortfolioSnapshot?
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var schwabState: BrokerConnectionState = .disconnected
    @Published private(set) var webullState: BrokerConnectionState = .disconnected
    @Published var isDetailExpanded = false

    private var refreshTimer: Timer?
    private var isRefreshScheduled = false

    private static let portfolioGlanceMigrationKey = "didMigratePortfolioGlance1.0.4"

    private init() {
        if hasAnyConnection, !UserDefaults.standard.bool(forKey: Self.portfolioGlanceMigrationKey) {
            Defaults[.showPortfolioGlance] = true
            UserDefaults.standard.set(true, forKey: Self.portfolioGlanceMigrationKey)
        }
    }

    var hasAnyConnection: Bool {
        SchwabBrokerService.shared.isConnected || WebullBrokerService.shared.isConnected
    }

    func startIfEnabled() {
        guard Defaults[.showPortfolioGlance] else {
            stop()
            return
        }
        updateConnectionStates()
        if hasAnyConnection {
            resumeRefreshTimer()
        }
    }

    func enableGlanceAndRefresh() {
        Defaults[.showPortfolioGlance] = true
        updateConnectionStates()
        resumeRefreshTimer()
    }

    func stop() {
        pauseRefreshTimer()
    }

    func pauseRefreshTimer() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isRefreshScheduled = false
    }

    func resumeRefreshTimer() {
        guard Defaults[.showPortfolioGlance], !isRefreshScheduled else { return }
        updateConnectionStates()
        isRefreshScheduled = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func updateConnectionStates() {
        schwabState = SchwabBrokerService.shared.isConnected ? .connected : .disconnected
        webullState = WebullBrokerService.shared.isConnected ? .connected : .disconnected
    }

    func connectSchwab() async {
        schwabState = .connecting
        lastError = nil
        do {
            try await SchwabBrokerService.shared.connect()
            schwabState = .connected
            enableGlanceAndRefresh()
        } catch {
            schwabState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func connectSchwab(manualRedirectURL: String) async {
        schwabState = .connecting
        lastError = nil
        do {
            try await SchwabBrokerService.shared.connect(manualRedirectURL: manualRedirectURL)
            schwabState = .connected
            enableGlanceAndRefresh()
        } catch {
            schwabState = .error(error.localizedDescription)
            lastError = error.localizedDescription
        }
    }

    func disconnectSchwab() {
        SchwabBrokerService.shared.disconnect()
        schwabState = .disconnected
        Task { await refresh() }
    }

    func connectWebull() async {
        webullState = .connecting
        lastError = nil
        do {
            try await WebullBrokerService.shared.connect {
                self.webullState = .awaitingVerification(
                    "Approve the SMS code in Webull → Menu → Messages → OpenAPI Notifications."
                )
            }
            webullState = .connected
            enableGlanceAndRefresh()
        } catch {
            if case WebullBrokerError.smsExpired = error {
                webullState = .awaitingVerification(error.localizedDescription ?? "SMS code expired. Tap Connect Webull again.")
            } else if case WebullBrokerError.awaitingVerification = error {
                webullState = .awaitingVerification("Open Webull → Menu → Messages → OpenAPI Notifications and enter the SMS code.")
            } else if case WebullBrokerError.sessionExpired = error {
                webullState = .error(error.localizedDescription ?? "Webull session expired.")
            } else {
                webullState = .error(error.localizedDescription)
            }
            lastError = error.localizedDescription
        }
    }

    func disconnectWebull() {
        WebullBrokerService.shared.disconnect()
        webullState = .disconnected
        Task { await refresh() }
    }

    func refresh() async {
        guard hasAnyConnection else {
            snapshot = nil
            isLoading = false
            return
        }
        guard Defaults[.showPortfolioGlance] else {
            isLoading = false
            return
        }

        isLoading = true
        defer { isLoading = false }

        var allHoldings: [PortfolioHolding] = []
        var connected: [BrokerKind] = []

        if SchwabBrokerService.shared.isConnected {
            do {
                let holdings = try await SchwabBrokerService.shared.fetchHoldings()
                allHoldings.append(contentsOf: holdings)
                connected.append(.schwab)
                schwabState = .connected
            } catch {
                schwabState = .error(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }

        if WebullBrokerService.shared.isConnected {
            do {
                let holdings = try await WebullBrokerService.shared.fetchHoldings()
                allHoldings.append(contentsOf: holdings)
                connected.append(.webull)
                webullState = .connected
            } catch {
                if case WebullBrokerError.sessionExpired = error {
                    WebullBrokerService.shared.disconnect()
                    webullState = .disconnected
                } else {
                    webullState = .error(error.localizedDescription)
                }
                lastError = error.localizedDescription
            }
        }

        let totalValue = allHoldings.reduce(0) { $0 + $1.marketValue }
        let totalDay = allHoldings.compactMap(\.dayChange).reduce(0, +)

        let newSnapshot = PortfolioSnapshot(
            totalMarketValue: totalValue,
            totalDayChange: totalDay,
            holdings: allHoldings.sorted { $0.marketValue > $1.marketValue },
            lastUpdated: Date(),
            brokersConnected: connected
        )
        snapshot = newSnapshot

        if isDetailExpanded, !newSnapshot.holdings.isEmpty {
            await PortfolioInsightsManager.shared.refresh(snapshot: newSnapshot)
        }
    }

    private var refreshInterval: TimeInterval {
        Defaults[.performanceMode] ? 900 : 300
    }
}
