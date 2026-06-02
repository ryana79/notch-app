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

    private var refreshTimer: Timer?

    private init() {
        updateConnectionStates()
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
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        Task { await refresh() }
    }

    func stop() {
        refreshTimer?.invalidate()
        refreshTimer = nil
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
            await refresh()
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
            await refresh()
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
            try await WebullBrokerService.shared.connect()
            webullState = .connected
            await refresh()
        } catch {
            if case WebullBrokerError.awaitingVerification = error {
                webullState = .awaitingVerification("Open Webull → Menu → Messages → OpenAPI Notifications and enter the SMS code.")
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
        guard Defaults[.showPortfolioGlance], hasAnyConnection else {
            snapshot = nil
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
                webullState = .error(error.localizedDescription)
                lastError = error.localizedDescription
            }
        }

        let totalValue = allHoldings.reduce(0) { $0 + $1.marketValue }
        let totalDay = allHoldings.compactMap(\.dayChange).reduce(0, +)

        snapshot = PortfolioSnapshot(
            totalMarketValue: totalValue,
            totalDayChange: totalDay,
            holdings: allHoldings.sorted { $0.marketValue > $1.marketValue },
            lastUpdated: Date(),
            brokersConnected: connected
        )
    }

    private var refreshInterval: TimeInterval {
        Defaults[.performanceMode] ? 900 : 300
    }
}
