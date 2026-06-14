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
    private var cancellables = Set<AnyCancellable>()
    private let connectionManager = BrokerageConnectionManager.shared

    private static let portfolioGlanceMigrationKey = "didMigratePortfolioGlance1.0.4"

    private init() {
        if hasAnyConnection, !UserDefaults.standard.bool(forKey: Self.portfolioGlanceMigrationKey) {
            Defaults[.showPortfolioGlance] = true
            UserDefaults.standard.set(true, forKey: Self.portfolioGlanceMigrationKey)
        }

        connectionManager.$schwabPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.schwabState = Self.mapPhase(phase)
            }
            .store(in: &cancellables)

        connectionManager.$webullPhase
            .receive(on: RunLoop.main)
            .sink { [weak self] phase in
                self?.webullState = Self.mapPhase(phase)
            }
            .store(in: &cancellables)

        schwabState = Self.mapPhase(connectionManager.schwabPhase)
        webullState = Self.mapPhase(connectionManager.webullPhase)
    }

    var hasAnyConnection: Bool {
        connectionManager.hasAnyConnection
    }

    func startIfEnabled() {
        guard Defaults[.showPortfolioGlance] else {
            stop()
            return
        }
        refreshConnectionStatesFromKeychain()
        if hasAnyConnection {
            scheduleRefreshTimer(deferImmediateRefresh: true)
        }
    }

    func refreshIfNeededOnNotchOpen() {
        guard Defaults[.showPortfolioGlance], hasAnyConnection else { return }
        guard snapshot == nil, !isLoading else { return }
        Task { await refresh() }
    }

    func enableGlanceAndRefresh() {
        Defaults[.showPortfolioGlance] = true
        refreshConnectionStatesFromKeychain()
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
        scheduleRefreshTimer(deferImmediateRefresh: snapshot != nil)
    }

    private func scheduleRefreshTimer(deferImmediateRefresh: Bool) {
        guard Defaults[.showPortfolioGlance], !isRefreshScheduled else { return }
        refreshConnectionStatesFromKeychain()
        isRefreshScheduled = true
        refreshTimer?.invalidate()
        refreshTimer = Timer.scheduledTimer(withTimeInterval: refreshInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in
                await self?.refresh()
            }
        }
        if !deferImmediateRefresh {
            Task { await refresh() }
        }
    }

    func updateConnectionStates() {
        refreshConnectionStatesFromKeychain()
    }

    func refreshConnectionStatesFromKeychain() {
        connectionManager.refreshPhasesFromStorage()
        schwabState = Self.mapPhase(connectionManager.schwabPhase)
        webullState = Self.mapPhase(connectionManager.webullPhase)
    }

    func warmBrokerTokensForRefresh() {
        KeychainTokenStore.migrateFromLegacyIfNeeded()
        BrokerTokenCache.warmSchwabFromKeychain()
        BrokerTokenCache.warmWebullFromKeychain()
    }

    func connectSchwab() async {
        lastError = nil
        await connectionManager.connectSchwab()
        lastError = connectionManager.lastError
        if connectionManager.schwabPhase.isConnected {
            enableGlanceAndRefresh()
        }
    }

    func connectSchwab(manualRedirectURL: String) async {
        lastError = nil
        await connectionManager.connectSchwab(manualRedirectURL: manualRedirectURL)
        lastError = connectionManager.lastError
        if connectionManager.schwabPhase.isConnected {
            enableGlanceAndRefresh()
        }
    }

    func disconnectSchwab() {
        connectionManager.disconnectSchwab()
        Task { await refresh() }
    }

    func connectWebull() async {
        lastError = nil
        await connectionManager.connectWebull {
            self.webullState = .awaitingVerification(
                "Approve the SMS code in Webull → Menu → Messages → OpenAPI Notifications."
            )
        }
        lastError = connectionManager.lastError
        if connectionManager.webullPhase.isConnected {
            enableGlanceAndRefresh()
        }
    }

    func disconnectWebull() {
        connectionManager.disconnectWebull()
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
        warmBrokerTokensForRefresh()

        var allHoldings: [PortfolioHolding] = []
        var connected: [BrokerKind] = []

        if SchwabBrokerService.shared.isConnected {
            do {
                let holdings = try await SchwabBrokerService.shared.fetchHoldings()
                allHoldings.append(contentsOf: holdings)
                connected.append(.schwab)
                schwabState = .connected
            } catch let error as BrokerageConnectionError {
                schwabState = .error(error.localizedDescription ?? "Schwab connection failed.")
                lastError = error.localizedDescription
                if error.requiresReauthorization {
                    connectionManager.disconnectSchwab()
                }
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
            } catch let error as BrokerageConnectionError {
                if error.requiresReauthorization {
                    connectionManager.disconnectWebull()
                    webullState = .disconnected
                } else {
                    webullState = .error(error.localizedDescription ?? "Webull connection failed.")
                }
                lastError = error.localizedDescription
            } catch {
                webullState = .error(error.localizedDescription)
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

    private static func mapPhase(_ phase: BrokerageConnectionPhase) -> BrokerConnectionState {
        switch phase {
        case .disconnected, .expired:
            return .disconnected
        case .authorizing, .exchangingCode, .refreshingToken:
            return .connecting
        case .connected:
            return .connected
        case .awaitingVerification(let message):
            return .awaitingVerification(message)
        case .failed(let message):
            return .error(message)
        }
    }
}
