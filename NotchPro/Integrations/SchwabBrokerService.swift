//
//  SchwabBrokerService.swift
//  NotchPro
//

import Defaults
import Foundation

struct PortfolioHolding: Identifiable, Equatable {
    let id: String
    let broker: BrokerKind
    let symbol: String
    let quantity: Double
    let marketValue: Double
    let dayChange: Double?
    let dayChangePercent: Double?
}

struct PortfolioSnapshot: Equatable {
    let totalMarketValue: Double
    let totalDayChange: Double
    let holdings: [PortfolioHolding]
    let lastUpdated: Date
    let brokersConnected: [BrokerKind]
}

enum BrokerKind: String, CaseIterable, Codable, Defaults.Serializable {
    case schwab
    case webull

    var displayName: String {
        switch self {
        case .schwab: return "Schwab"
        case .webull: return "Webull"
        }
    }
}

enum BrokerConnectionState: Equatable {
    case disconnected
    case connecting
    case awaitingVerification(String)
    case connected
    case error(String)
}

@MainActor
final class SchwabBrokerService {
    static let shared = SchwabBrokerService()

    private let baseURL = "https://api.schwabapi.com"
    private let session: URLSession

    private init() {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        config.timeoutIntervalForResource = 30
        session = URLSession(configuration: config)
    }

    var isConnected: Bool {
        BrokerConnectionCache.schwabConnected
    }

    func disconnect() {
        BrokerageConnectionManager.shared.disconnectSchwab()
    }

    func fetchHoldings() async throws -> [PortfolioHolding] {
        let token = try await SchwabAuthService.shared.validAccessToken()
        let accountHashes = try await fetchAccountHashes(accessToken: token)
        var holdings: [PortfolioHolding] = []

        for hash in accountHashes {
            let accountHoldings = try await fetchPositions(accountHash: hash, accessToken: token)
            holdings.append(contentsOf: accountHoldings)
        }

        return holdings
    }

    private func fetchAccountHashes(accessToken: String) async throws -> [String] {
        var request = URLRequest(url: URL(string: "\(baseURL)/trader/v1/accounts/accountNumbers")!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response = try await BrokerHTTPClient.data(for: request)
        if response.statusCode == 401 { throw BrokerageConnectionError.sessionExpired }
        guard (200...299).contains(response.statusCode) else {
            throw BrokerageConnectionError.apiHTTP(status: response.statusCode, debugCode: "schwab_accounts")
        }

        guard let accounts = try JSONSerialization.jsonObject(with: response.data) as? [[String: Any]] else {
            throw BrokerageConnectionError.providerMessage("Unexpected response from Schwab.", debugCode: "schwab_accounts_json")
        }

        return accounts.compactMap { $0["hashValue"] as? String }
    }

    private func fetchPositions(accountHash: String, accessToken: String) async throws -> [PortfolioHolding] {
        var components = URLComponents(string: "\(baseURL)/trader/v1/accounts/\(accountHash)")!
        components.queryItems = [URLQueryItem(name: "fields", value: "positions")]
        var request = URLRequest(url: components.url!)
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let response = try await BrokerHTTPClient.data(for: request)
        if response.statusCode == 401 { throw BrokerageConnectionError.sessionExpired }
        guard (200...299).contains(response.statusCode) else {
            throw BrokerageConnectionError.apiHTTP(status: response.statusCode, debugCode: "schwab_positions")
        }

        guard let json = try JSONSerialization.jsonObject(with: response.data) as? [String: Any],
              let securitiesAccount = json["securitiesAccount"] as? [String: Any],
              let positions = securitiesAccount["positions"] as? [[String: Any]] else {
            return []
        }

        return positions.compactMap { position in
            guard let instrument = position["instrument"] as? [String: Any],
                  let symbol = instrument["symbol"] as? String else { return nil }

            let quantity = (position["longQuantity"] as? Double) ?? 0
            let marketValue = (position["marketValue"] as? Double) ?? 0
            let dayPL = position["currentDayProfitLoss"] as? Double
            let dayPLPercent = position["currentDayProfitLossPercentage"] as? Double

            return PortfolioHolding(
                id: "schwab-\(symbol)",
                broker: .schwab,
                symbol: symbol,
                quantity: quantity,
                marketValue: marketValue,
                dayChange: dayPL,
                dayChangePercent: dayPLPercent
            )
        }
    }
}
